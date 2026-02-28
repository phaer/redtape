# red-tape: Design Document

## Summary

**red-tape** is a convention-based project builder (like blueprint) on top of
the adios module system. Filesystem layout drives output generation. Adios
provides memoization across systems and explicit dependency tracking.

Supports both flakes and traditional `default.nix` (npins/niv).

---

## 1. What Blueprint Does (Feature Inventory)

| Feature | Filesystem convention |
|---------|----------------------|
| Packages | `packages/<name>.nix`, `packages/<name>/`, `package.nix` |
| DevShells | `devshells/<name>.nix`, `devshell.nix`, `devshell.toml` |
| Checks | `checks/<name>.nix` (+ auto-checks from packages, devshells, hosts) |
| Hosts | `hosts/<name>/configuration.nix` (NixOS), `darwin-configuration.nix`, `system-configuration.nix`, `rpi-configuration.nix`, `default.nix` (escape hatch) |
| Home Manager | `hosts/<name>/users/<user>.nix` or `hosts/<name>/users/<user>/home-configuration.nix` |
| Modules | `modules/<type>/<name>.nix` → `nixosModules`, `darwinModules`, `homeModules`, `modules` |
| Templates | `templates/<name>/` |
| Lib | `lib/default.nix` |
| Formatter | `formatter.nix` (fallback: `nixfmt-tree`) |

Each per-system file receives `{ pkgs, system, pname, perSystem, flake, inputs }` via callPackage.

Configuration: `prefix` (relocate root), `systems`, `nixpkgs.config`, `nixpkgs.overlays`.

---

## 2. Architecture

The core insight: **discovery is system-independent**. Scanning the filesystem
(`readDir`, `pathExists`) doesn't need `pkgs`. So we split the work into two
layers:

1. **Discover** — scan once, return paths (memoized across systems)
2. **Build** — import and evaluate per system (re-evaluated via adios override)

### Architecture Layers

```
Entry point (mk-red-tape.nix)
│
├── discover(src)              ← pure function, not an adios module
│   Returns { packages, devshells, checks, formatter, ... } paths
│
├── adios module tree:
│   / (root)
│   ├── /nixpkgs               ← system + pkgs (overridden per-system)
│   ├── /packages              ← per-system: callPackage discovered packages
│   ├── /devshells             ← per-system: build discovered devshells
│   ├── /formatter             ← per-system: formatter derivation
│   ├── /checks                ← per-system: user-defined checks
│   ├── /hosts                 ← Phase 2: system-agnostic host configs
│   ├── /modules-export        ← Phase 2: export NixOS/darwin/home modules
│   ├── /templates             ← Phase 2: export templates
│   └── /lib-export            ← Phase 2: export lib/default.nix
│
└── Result assembly            ← entry point calls modules, merges + transposes
```

**Key insight:** In adios, `inputs` gives a dependency's **options**, not its
impl results. Therefore:

- **Discovery** is a plain function (not an adios module) — its results are
  passed as options to per-system modules by the entry point.
- **Result assembly** (auto-checks from packages/devshells, transposition)
  happens in the entry point, not in an adios module.
- **Per-system modules** only depend on `/nixpkgs`. Discovered paths and
  extraScope are passed as options.

When overriding `/nixpkgs` for a new system, adios re-evaluates only the
per-system modules. Discovery is evaluated once (it's outside the tree).

---

## 3. `self` and the Flake Fixpoint

`self` (the flake's own output) is needed in two places:

1. **Host configs**: `perSystem.self.myPackage` in a NixOS configuration
2. **Exported modules**: publisher-args injection (`{ flake, inputs }`)

**Key decision: `self` stays outside the adios dependency graph.**

`self` is never an adios module option or input. Instead, the entry point
captures it and threads it through conventional Nix mechanisms:

- **callPackage scope**: per-system files receive `perSystem.self.<name>`
  through the scope, which resolves `self.packages.${system}` lazily
- **host specialArgs**: `nixosSystem { specialArgs = { flake, inputs, ... }; }`
- **module publisher-args**: `import modulePath { flake, inputs }`

This means:
- Adios never tracks `self` as a dependency → no memoization interference
- No fixpoint concerns inside the module tree
- Nix's own lazy evaluation handles the `self` reference naturally (same as
  blueprint and flake-parts do today)

The entry point constructs `self` via the standard flake fixpoint:
```nix
outputs = inputs: let result = red-tape { inherit inputs; self = result; }; in result;
```

In traditional mode there is no multi-output fixpoint — `self` is simply the
return value of `default.nix`.

---

## 4. Modules

### 4.1 `/nixpkgs`

Data-only module (no `impl`). Provides `system` and `pkgs` to downstream modules.

```nix
{ types, ... }: {
  name = "nixpkgs";
  options = {
    system = { type = types.string; };
    pkgs   = { type = types.attrs; };
  };
}
```

The entry point handles `nixpkgs.config` / `nixpkgs.overlays` — if set, it
calls `import nixpkgs { inherit system; config = ...; overlays = ...; }`
instead of using `legacyPackages`.

### 4.2 `discover` (plain function, not an adios module)

A pure function that scans the filesystem and returns paths. Not an adios
module because its results need to be passed as options to per-system modules
(in adios, `inputs` gives options, not impl results).

```nix
src: {
  packages  = scanDir (src + "/packages") // optionalFile (src + "/package.nix") "default";
  devshells = scanDir (src + "/devshells") // optionalFile (src + "/devshell.nix") "default";
  checks    = scanDir (src + "/checks");
  formatter = optionalPath (src + "/formatter.nix");
  # Phase 2: hosts, modules, templates, lib
}
```

### 4.3 `/packages`

Per-system. Discovered paths and extraScope are passed as **options** by the
entry point. Depends on `/nixpkgs` for `pkgs` and `system`.

```nix
{ types, ... }: {
  name = "packages";
  inputs.nixpkgs = { path = "/nixpkgs"; };
  options = {
    discovered = { type = types.attrs; default = {}; };
    extraScope = { type = types.attrs; default = {}; };  # perSystem, flake, etc.
  };
  impl = { inputs, options, ... }:
    let
      buildPkg = pname: entry: callPkg entry.path { inherit pname; };
    in
    { packages = mapAttrs buildPkg options.discovered; ... };
}
```

### 4.4 `/devshells`

Per-system. Same pattern as packages. TOML shells require `inputs.devshell`.

### 4.5 `/formatter`

Per-system. Imports `formatter.nix` or falls back to `pkgs.nixfmt-tree`.

### 4.6 `/checks`

Per-system. Handles user-defined checks from `checks/`. Auto-checks
(packages with `pkgs-` prefix, devshells with `devshell-` prefix, host
closures, `lib.tests`) are assembled by the entry point after calling
each module, since cross-module result access isn't available through
adios inputs.

### 4.7 `/hosts`

System-agnostic (no `/nixpkgs` dependency). Each host's `nixpkgs.hostPlatform`
determines its system internally.

Dispatches by filename:
- `configuration.nix` → `nixpkgs.lib.nixosSystem`
- `darwin-configuration.nix` → `nix-darwin.lib.darwinSystem`
- `system-configuration.nix` → `system-manager.lib.makeSystemConfig`
- `rpi-configuration.nix` → `nixos-raspberrypi.lib.nixosSystem`
- `default.nix` → user returns `{ class, value }`

Host configs receive `{ flake, inputs, hostName, perSystem }` via specialArgs
(injected by the entry point, not through adios).

Home-manager users under `hosts/<name>/users/` are auto-wired when the
`home-manager` input exists.

### 4.8 `/modules-export`, `/templates`, `/lib-export`

System-agnostic, thin wrappers. Read paths from `/discover`, import or
re-export them. Module publisher-args injection (`{ flake, inputs }`) is
handled here.

### 4.9 Result Assembly (in the entry point, not an adios module)

The entry point calls each module through the tree, collects their results,
assembles auto-checks from packages/devshells, and transposes per-system
outputs to flake shape (`packages.<system>.<name>`, etc.).

---

## 5. Entry Points

### 5.1 Flake Mode

```nix
# User's flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    red-tape.url = "github:phaer/red-tape";
  };
  outputs = inputs: let result = inputs.red-tape {
    inherit inputs;
    prefix = "nix/";                          # optional
    systems = [ "x86_64-linux" "aarch64-darwin" ]; # optional
    nixpkgs.config.allowUnfree = true;        # optional
  }; in result;
}
```

The entry point:

1. Resolves `src` from `prefix`
2. Builds `perSystem` scope (maps each input to its per-system packages)
3. Constructs the adios module tree (all modules from §4)
4. Evaluates for the first system (full tree eval)
5. Overrides `/nixpkgs` for each remaining system (adios memoizes unchanged modules)
6. Transposes per-system results into flake output shape
7. Merges in system-agnostic outputs

The `perSystem` and `self`/`flake`/`inputs` values are injected into the
callPackage scope and host specialArgs **outside** the adios tree. They are
constructed fresh for each system at the entry-point level.

### 5.2 Traditional Mode

```nix
# User's default.nix
{
  __sources ? import ./npins,
  pkgs ? import __sources.nixpkgs {},
  red-tape ? import __sources.red-tape,
}:
red-tape.eval {
  inherit pkgs;
  src = ./.;
}
```

Same module tree, single system, no transposition. Returns a flat attrset:
```nix
{ packages = { ... }; devShells = { ... }; checks = { ... }; shell = devShells.default; ... }
```

---

## 6. Shared Library

Plain functions (not adios modules), imported where needed:

| File | Purpose |
|------|---------|
| `lib/scan-dir.nix` | `readDir` → `{ name = { path, type }; }` for `.nix` files + dirs |
| `lib/scan-hosts.nix` | Host directory structure + user detection |
| `lib/filter-platforms.nix` | Filter packages by `meta.platforms` |
| `lib/transpose.nix` | `{ system → { cat.name } }` → `{ cat → { system → { name } } }` |

---

## 7. Extensibility

### User Modules

```nix
red-tape {
  inherit inputs;
  extraModules = {
    my-thing = { types, ... }: {
      inputs.nixpkgs = { path = "/nixpkgs"; };
      impl = { inputs, ... }: { packages.my-thing = ...; };
    };
  };
}
```

Added to the tree before evaluation. The collector picks them up automatically.

### Third-Party Module Config

Flat `config` parameter, maps to adios tree options:
```nix
red-tape {
  inherit inputs;
  config.treefmt = { projectRootFile = "flake.nix"; };
  config."treefmt/nixfmt" = { enable = true; };
}
```

### adios-contrib Compatibility

Users can compose with existing adios-contrib modules:
```nix
red-tape {
  inherit inputs;
  adiosModules = [ adios-contrib ];
}
```

### Optional Features

Home-manager, TOML devshells, system-manager, etc. are only loaded when
the corresponding flake input exists. No errors for missing optional inputs.

---

## 8. Implementation Phases

### Phase 1: Core (MVP)
- `/nixpkgs`, `/discover` (packages + devshells + formatter), `/packages`,
  `/devshells`, `/formatter`, `/collector`
- Flake + traditional entry points
- Basic tests

### Phase 2: Full Discovery
- `/checks` with auto-check assembly
- `/hosts` (NixOS + darwin)
- `/modules-export`, `/templates`, `/lib-export`
- `prefix` support

### Phase 3: Extended
- Home-manager auto-wiring
- TOML devshells, system-manager, rpi hosts
- `perSystem` cross-input resolution
- `lib.tests` nix-unit integration
- adios-contrib compatibility

### Phase 4: Polish
- Error messages, documentation, templates, benchmarks

---

## 9. File Structure

```
red-tape/
├── default.nix            # Traditional entry point
├── flake.nix              # Flake entry point
├── shell.nix              # Dev shell
├── modules/
│   ├── nixpkgs.nix        # /nixpkgs — data-only, provides pkgs + system
│   ├── discover.nix       # Plain function (not adios module) — filesystem scan
│   ├── packages.nix       # /packages — per-system callPackage
│   ├── devshells.nix      # /devshells — per-system shell builder
│   ├── formatter.nix      # /formatter — per-system formatter
│   ├── checks.nix         # /checks — per-system user-defined checks
│   ├── hosts.nix          # Phase 2: /hosts
│   ├── home-users.nix     # Phase 3: home-manager wiring
│   ├── modules-export.nix # Phase 2: module export
│   ├── templates.nix      # Phase 2: template export
│   └── lib-export.nix     # Phase 2: lib export
├── lib/
│   ├── mk-red-tape.nix    # Core logic: tree construction + result assembly
│   ├── scan-dir.nix       # readDir → { name = { path, type }; }
│   ├── filter-platforms.nix
│   └── transpose.nix      # { system → cats } → { cat → systems }
└── tests/
    ├── prelude.nix         # Shared test setup (adios, mock pkgs)
    ├── scan-dir.nix        # scan-dir unit tests
    ├── transpose.nix       # transpose unit tests
    ├── discover.nix        # discover function tests
    ├── integration.nix     # full tree evaluation tests
    ├── traditional.nix     # traditional eval entry point tests
    ├── run.sh              # test runner script
    └── fixtures/           # mock project trees
```

---

## 10. Design Decisions

### D1. Discovery is a plain function, not an adios module

Discovery scans the filesystem and returns paths. It's a plain Nix function
because in adios, `inputs` gives a dependency's *options*, not its impl
results. To pass discovery results to per-system modules, they must be
injected as options by the entry point — making an adios module unnecessary.

This also means discovery is naturally memoized: it runs once per entry point
call, and its results are passed identically to all system evaluations.

Source filtering (e.g., `lib.fileset`) happens at the derivation level inside
user package files, not during discovery. Discovery only returns paths.

### D2. `perSystem` injected at the entry point

Not an adios module. The entry point builds `perSystem` (mapping each flake
input to its `packages.<system>` + `legacyPackages.<system>`) and injects it
through the callPackage scope. Keeps the adios tree minimal.

### D3. Same module tree for flake and traditional mode

One code path. Traditional mode = single system, no transposition.

### D4. `self` stays outside the adios graph

`self` is never an adios option or input. It's threaded through callPackage
scopes and host specialArgs by the entry point. This avoids any memoization
interference — adios has no knowledge of the fixpoint, and Nix's lazy
evaluation resolves `self` references naturally.

Per-system `self'` (e.g., `self'.packages.hello`) is computed at the entry
point as `self.packages.${system}` and injected into the callPackage scope
alongside `perSystem`. System-agnostic modules (hosts) access `self` directly
for non-per-system outputs (e.g., `self.nixosModules.shared`).

### D5. Flat `config` parameter for third-party modules

Maps directly to adios tree options. No special machinery needed.
