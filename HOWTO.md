# How to use red-tape

A guide for Nix users who know flakes and NixOS modules but haven't used
adios or convention-based project builders before.

## The problem

A typical `flake.nix` for a project with a package, devshell, formatter,
NixOS module, and a host configuration looks something like this:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        pkgs = nixpkgs.legacyPackages.${system};
        inherit system;
      });
    in {
      packages = forAllSystems ({ pkgs, ... }: {
        default = pkgs.callPackage ./package.nix {};
        widget = pkgs.callPackage ./packages/widget.nix {};
      });

      devShells = forAllSystems ({ pkgs, ... }: {
        default = pkgs.mkShell { packages = [ pkgs.nodejs ]; };
      });

      formatter = forAllSystems ({ pkgs, ... }: pkgs.nixfmt-tree);

      checks = forAllSystems ({ pkgs, system, ... }: {
        # Manually wire every package as a check...
        pkgs-default = self.packages.${system}.default;
        pkgs-widget = self.packages.${system}.widget;
        # ...and every devshell too
        devshell-default = self.devShells.${system}.default;
      });

      nixosModules.server = ./modules/nixos/server.nix;

      nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
        modules = [ ./hosts/myhost/configuration.nix ];
        specialArgs = { inherit self; };
      };
    };
}
```

This is tedious. Every new package needs wiring in three places (packages,
checks, flake.nix). The `forAllSystems` dance repeats for every output type.
Adding a devshell means updating checks too. It doesn't scale.

## The solution

With red-tape, you just put files in the right place:

```nix
# flake.nix — the entire thing
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.red-tape.url = "github:you/red-tape";

  outputs = inputs: inputs.red-tape.lib { inherit inputs; };
}
```

```
my-project/
├── flake.nix                          # ← 6 lines above
├── package.nix                        # → packages.default + checks.pkgs-default
├── packages/widget.nix                # → packages.widget + checks.pkgs-widget
├── devshell.nix                       # → devShells.default + checks.devshell-default
├── hosts/myhost/configuration.nix     # → nixosConfigurations.myhost
└── modules/nixos/server.nix           # → nixosModules.server
```

No `forAllSystems`. No manual check wiring. Add a file, get an output.

## How files are called

Every `.nix` file under `packages/`, `devshells/`, `checks/`, and
`formatter.nix` is called like `callPackage` — red-tape inspects the
function arguments and passes only what's requested:

```nix
# packages/widget.nix
{ pkgs, lib, pname, ... }:
pkgs.stdenv.mkDerivation {
  inherit pname;
  version = "1.0";
  src = ./.;
  # ...
}
```

Available arguments:

| Arg | Value |
|-----|-------|
| `pkgs` | nixpkgs for the current system |
| `lib` | `pkgs.lib` |
| `system` | e.g. `"x86_64-linux"` |
| `pname` | derived from filename (`widget.nix` → `"widget"`) |
| `flake` | the flake's `self` |
| `inputs` | all flake inputs |
| `perSystem` | packages from other inputs (see below) |

You only take what you need. `{ pkgs, ... }:` is the common case.

## Walkthrough: building a project from scratch

### 1. A package

```nix
# package.nix
{ pkgs, pname, ... }:
pkgs.writeShellScriptBin pname ''
  echo "Hello!"
''
```

This becomes `packages.default` (because the file is `package.nix`, not
`packages/something.nix`). It also automatically becomes `checks.pkgs-default`.

```console
$ nix build       # builds packages.default
$ nix flake check # runs checks.pkgs-default (same derivation)
```

### 2. More packages

```nix
# packages/widget.nix
{ pkgs, pname, ... }:
pkgs.stdenv.mkDerivation {
  inherit pname;
  src = ./.;
}
```

```nix
# packages/cli/default.nix   (directory form)
{ pkgs, pname, ... }:
pkgs.buildGoModule {
  inherit pname;
  src = ./.;
}
```

These become `packages.widget` and `packages.cli`. Both are also checks.
If a package has `passthru.tests`, those become checks too:

```
packages.widget           → checks.pkgs-widget
packages.cli              → checks.pkgs-cli
packages.cli.passthru.tests.integration → checks.pkgs-cli-integration
```

### 3. A devshell

```nix
# devshell.nix
{ pkgs, ... }:
pkgs.mkShell {
  packages = [ pkgs.nodejs pkgs.typescript ];
}
```

This becomes `devShells.default` and `checks.devshell-default`.

```console
$ nix develop  # enters the shell
```

For multiple devshells, use a directory:

```nix
# devshells/backend.nix
{ pkgs, ... }:
pkgs.mkShell { packages = [ pkgs.go ]; }
```

```console
$ nix develop .#backend
```

### 4. A formatter

```nix
# formatter.nix
{ pkgs, ... }:
pkgs.nixfmt-tree
```

If you don't create this file, red-tape falls back to `nixfmt-tree`
automatically. You only need it to choose a different formatter.

```console
$ nix fmt
```

### 5. Checks

Auto-checks from packages and devshells are usually enough. For custom
checks:

```nix
# checks/lint.nix
{ pkgs, pname, ... }:
pkgs.runCommand pname {} ''
  ${pkgs.statix}/bin/statix check ${./.}
  touch $out
''
```

### 6. NixOS hosts

```nix
# hosts/myhost/configuration.nix
{ config, pkgs, flake, inputs, hostName, ... }:
{
  networking.hostName = hostName;  # "myhost" — derived from directory name
  # ...
}
```

red-tape calls `nixpkgs.lib.nixosSystem` for you, passing
`{ flake, inputs, hostName }` as `specialArgs`. Your configuration modules
can access all flake inputs directly.

```console
$ nixos-rebuild switch --flake .#myhost
```

#### Darwin hosts

```nix
# hosts/mymac/darwin-configuration.nix
{ config, pkgs, flake, inputs, hostName, ... }:
{
  # nix-darwin configuration
}
```

Requires `inputs.nix-darwin` in your flake inputs. red-tape calls
`nix-darwin.lib.darwinSystem` automatically based on the filename.

#### Custom host escape hatch

If you need full control (custom system builder, unusual module system):

```nix
# hosts/weird/default.nix
{ flake, inputs, hostName }:
{
  class = "nixos";  # or "nix-darwin"
  value = inputs.nixpkgs.lib.nixosSystem {
    # your custom setup
  };
}
```

### 7. NixOS/darwin/home-manager modules

```nix
# modules/nixos/server.nix
{ config, lib, pkgs, ... }:
{
  options.services.myapp = { ... };
  config = { ... };
}
```

This is re-exported as `nixosModules.server` — the path to the file.
Consumers use it as `inputs.your-flake.nixosModules.server`.

The directory name determines the output key:

| Directory | Output |
|-----------|--------|
| `modules/nixos/` | `nixosModules` |
| `modules/darwin/` | `darwinModules` |
| `modules/home/` | `homeModules` |

If a module file needs to know about the flake (e.g. to provide a default
package), use publisher args:

```nix
# modules/nixos/myapp.nix
{ flake, inputs }:    # ← called once at export time
{ config, lib, ... }: # ← this is the actual NixOS module
{
  options.services.myapp.package = lib.mkOption {
    default = flake.packages.${config.nixpkgs.hostPlatform.system}.default;
  };
}
```

### 8. Overlays

```nix
# overlay.nix — becomes overlays.default
{ ... }:
final: prev: {
  my-patched-pkg = prev.something.overrideAttrs { ... };
}
```

```nix
# overlays/extra-tools.nix — becomes overlays.extra-tools
{ ... }:
final: prev: {
  my-tool = final.callPackage ./packages/my-tool.nix {};
}
```

Overlay files can accept `{ lib, flake, inputs, ... }` but **not**
`pkgs` or `system` — overlays are system-agnostic functions that receive
their pkgs as `final`/`prev`.

### 9. Templates

```
templates/
├── default/
│   ├── flake.nix     # description read from here
│   └── ...
└── minimal/
    ├── flake.nix
    └── ...
```

```console
$ nix flake init -t your-flake#minimal
```

### 10. Library functions

```nix
# lib/default.nix
{ flake, inputs }:
{
  greet = name: "Hello, ${name}!";
}
```

Becomes `lib` in the flake output. The `{ flake, inputs }` wrapper is
optional — a plain attrset works too.

## Using packages from other flake inputs

The `perSystem` argument merges `packages` and `legacyPackages` from all
inputs for the current system:

```nix
# devshell.nix
{ pkgs, perSystem, ... }:
pkgs.mkShell {
  packages = [
    perSystem.some-tool-flake.default
  ];
}
```

This avoids the `inputs.foo.packages.${system}.bar` boilerplate.

## Configuration options

```nix
# flake.nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.red-tape.url = "github:you/red-tape";

  outputs = inputs: inputs.red-tape.lib {
    inherit inputs;

    # Limit target systems (default: linux + darwin, x86_64 + aarch64)
    systems = [ "x86_64-linux" ];

    # Nixpkgs configuration
    nixpkgs = {
      config.allowUnfree = true;
      overlays = [ my-overlay ];
    };

    # Source root for monorepos
    prefix = "nix";  # look in ./nix/ instead of ./
  };
}
```

## Comparison with flake-parts

If you've used [flake-parts](https://flake.parts), here's how red-tape
differs:

### Convention vs. configuration

flake-parts gives you a module system to *configure* outputs:

```nix
# flake-parts
perSystem = { pkgs, ... }: {
  packages.widget = pkgs.callPackage ./widget.nix {};
  devShells.default = pkgs.mkShell { ... };
  checks.widget = self'.packages.widget;
};
```

red-tape gives you file conventions — you write the `.nix` file and the
output appears:

```
# red-tape
packages/widget.nix    → packages.widget + checks.pkgs-widget
devshell.nix           → devShells.default + checks.devshell-default
```

No registration step, no `self'`, no `perSystem` block.

### Module system

flake-parts uses the NixOS module system (`lib.evalModules`). You define
options with `lib.mkOption`, merge with `lib.mkMerge`, compose with imports.
This is powerful but carries the weight of the full module system — deep
stack traces, `lib.mkIf`, `lib.mkDefault`, priority ordering.

red-tape uses [adios](https://github.com/adisbladis/adios), a leaner
alternative. Adios modules declare explicit dependencies and options with
types, but there's no merging, no priorities, no `mkIf`. Each module is
a function that receives its inputs and options and returns a result.
You don't write adios modules to use red-tape — the conventions handle it.

### Evaluation model

flake-parts evaluates the full module tree for each system. If you have
4 systems, `perSystem` runs 4 times with 4 separate module evaluations.

red-tape evaluates once, then uses adios `override` for subsequent systems.
Modules that don't depend on the system (overlays, hosts, module exports)
are evaluated once and shared. In practice, this means system-agnostic
work isn't repeated.

### Escape hatches

flake-parts: write a module, use `config`, `options`, `lib.mkOption`.

red-tape: for hosts, use a `default.nix` escape hatch that returns
`{ class, value }`. For everything else, use `extraModules` to add
custom adios modules, or `config` to pass options to them.

### Third-party integrations

flake-parts has a large ecosystem of modules (treefmt, devenv, hercules-ci,
etc.) that plug into its module system.

red-tape is minimal by design. It handles the common outputs. Niche
integrations belong in contrib modules or your own `extraModules`.

### When to use which

**Use red-tape** if you want zero-boilerplate flake outputs from file
conventions and don't need the NixOS module system's merging semantics
for your flake configuration.

**Use flake-parts** if you need deep module composition, third-party
integrations, or are already invested in its ecosystem.

### Side-by-side

```nix
# ── flake-parts ──────────────────────────────
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [ "x86_64-linux" "aarch64-darwin" ];
    perSystem = { pkgs, self', ... }: {
      packages.default = pkgs.callPackage ./package.nix {};
      packages.widget = pkgs.callPackage ./packages/widget.nix {};
      devShells.default = pkgs.mkShell {
        packages = [ pkgs.nodejs ];
      };
      checks = {
        pkg-default = self'.packages.default;
        pkg-widget = self'.packages.widget;
        devshell = self'.devShells.default;
      };
      formatter = pkgs.nixfmt-tree;
    };
    flake = {
      nixosModules.server = ./modules/nixos/server.nix;
      nixosConfigurations.myhost = inputs.nixpkgs.lib.nixosSystem {
        modules = [ ./hosts/myhost/configuration.nix ];
      };
    };
  };
}
```

```nix
# ── red-tape ─────────────────────────────────
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    red-tape.url = "github:you/red-tape";
  };
  outputs = inputs: inputs.red-tape.lib { inherit inputs; };
}
# Then just have the files:
#   package.nix  packages/widget.nix  devshell.nix
#   hosts/myhost/configuration.nix  modules/nixos/server.nix
```

Same outputs. The red-tape version has a 5-line `flake.nix` and no
registration boilerplate — the filesystem *is* the configuration.

## Comparison with blueprint

[blueprint](https://github.com/numtide/blueprint) is the closest relative
to red-tape — both are convention-based and share the same core idea.
If you've used blueprint, here's what's the same, what's different, and
why you might choose one over the other.

### What's the same

The filesystem conventions are nearly identical:

| Convention | blueprint | red-tape |
|-----------|-----------|----------|
| `package.nix` | `packages.default` | `packages.default` |
| `packages/<name>.nix` | `packages.<name>` | `packages.<name>` |
| `packages/<name>/default.nix` | `packages.<name>` | `packages.<name>` |
| `devshell.nix` | `devShells.default` | `devShells.default` |
| `devshells/<name>.nix` | `devShells.<name>` | `devShells.<name>` |
| `formatter.nix` | `formatter` | `formatter` |
| `checks/<name>.nix` | `checks.<name>` | `checks.<name>` |
| `hosts/*/configuration.nix` | `nixosConfigurations.*` | `nixosConfigurations.*` |
| `hosts/*/darwin-configuration.nix` | `darwinConfigurations.*` | `darwinConfigurations.*` |
| `hosts/*/default.nix` | escape hatch `{ class, value }` | escape hatch `{ class, value }` |
| `modules/nixos/<name>.nix` | `nixosModules.<name>` | `nixosModules.<name>` |
| `modules/darwin/<name>.nix` | `darwinModules.<name>` | `darwinModules.<name>` |
| `modules/home/<name>.nix` | `homeModules.<name>` | `homeModules.<name>` |
| `templates/<name>/` | `templates.<name>` | `templates.<name>` |
| `lib/default.nix` | `lib` | `lib` |

Per-system file arguments are also identical: `pkgs`, `lib`, `system`,
`pname`, `flake`, `inputs`, `perSystem`.

A blueprint project can be migrated to red-tape (or vice versa) by
changing a single line in `flake.nix`.

### What's different

#### Auto-checks

Both wire packages as checks. Blueprint also wires NixOS/darwin host
closures as checks (`checks.<system>.nixos-<hostname>`). Red-tape does
not — system closures are expensive to build and belong in CI configuration
rather than `nix flake check`.

#### Overlays

Red-tape adds `overlay.nix` / `overlays/` → `overlays.*`, which blueprint
doesn't support. Blueprint has no `overlays` flake output convention.

#### Formatter fallback

Red-tape falls back to `nixfmt-tree` when no `formatter.nix` exists.
Blueprint requires an explicit `formatter.nix`.

#### Modules re-export

Blueprint also exposes `modules.<type>.<name>` for all module types, not
just the well-known ones. Red-tape only re-exports the three well-known
aliases (`nixosModules`, `darwinModules`, `homeModules`).

#### Features red-tape intentionally omits

| Feature | Blueprint | Red-tape |
|---------|-----------|----------|
| TOML devshells | ✓ (via `devshells/<name>.toml`) | ✗ |
| Home-manager users under hosts | ✓ (`hosts/*/users/*.nix`) | ✗ |
| System-manager hosts | ✓ (`hosts/*/system-configuration.nix`) | ✗ |
| Raspberry Pi hosts | ✓ (`hosts/*/rpi-configuration.nix`) | ✗ |

These belong in contrib modules and aren't part of red-tape's core.

#### Implementation

Blueprint is ~400 lines of Nix using `lib.genAttrs` for multi-system
evaluation, with no special memoization — every system is evaluated
independently.

Red-tape uses [adios](https://github.com/adisbladis/adios) for memoization:
the first system is evaluated in full, subsequent systems reuse that
evaluation and only re-run modules that depend on `system`/`pkgs`. System-
agnostic work (hosts, overlays, module re-export) is evaluated exactly once.

#### Flake inputs

Blueprint requires `nixpkgs` and `systems` as flake inputs. Red-tape has
no flake inputs at all — its dependencies are pinned via npins internally,
and consumers provide their own `nixpkgs` through the `inputs` argument.

### When to use which

**Use red-tape** if you want the same conventions with adios memoization,
overlays support, a minimal formatter fallback, and no dependency on the
blueprint flake.

**Use blueprint** if you need home-manager user auto-wiring, TOML devshells,
system-manager or Raspberry Pi hosts, or prefer a more actively maintained
upstream with a larger community.

## Writing custom modules

red-tape is built on [adios](https://github.com/adisbladis/adios) modules.
Every output type is an adios module — you can add your own via `extraModules`
and they integrate seamlessly with the rest of the tree.

### What an adios module looks like

An adios module is a plain Nix attrset:

```nix
{
  name = "my-module";           # identifies this module in the tree

  inputs = {                    # other modules this one depends on
    nixpkgs = { path = "/nixpkgs"; };
  };

  options = {                   # typed options, set by the entry point
    discovered = { type = types.attrs; default = {}; };
    extraScope = { type = types.attrs; default = {}; };
  };

  impl = { inputs, options, ... }:  # the computation
    {
      # return value merged into flake outputs by collectAgnostic
    };
}
```

`inputs` wires other modules' options into this one. `options` are typed
values passed in from outside. `impl` receives both and returns the result.

Modules with no `inputs.nixpkgs` are **system-agnostic** — adios evaluates
them once and their result is merged directly into the top-level flake
outputs by `collectAgnostic`. Modules that depend on `/nixpkgs` are
**per-system** and their results are transposed.

### Example: nix-on-droid support

[nix-on-droid](https://github.com/nix-community/nix-on-droid) manages
Android devices via Nix. It has its own flake output convention:

```nix
nixOnDroidConfigurations.default = nix-on-droid.lib.nixOnDroidConfiguration {
  pkgs = import nixpkgs { system = "aarch64-linux"; };
  modules = [ ./nix-on-droid.nix ];
};
```

red-tape's `hosts` module only handles `nixos` and `nix-darwin` classes.
To add nix-on-droid, we use the **escape hatch** for discovery and a
**custom adios module** to produce the right output key.

#### Step 1: Use the escape hatch for the host

The `hosts/*/default.nix` escape hatch lets you return any `{ class, value }`:

```nix
# hosts/myphone/default.nix
{ flake, inputs, hostName }:
{
  class = "nix-on-droid";
  value = inputs.nix-on-droid.lib.nixOnDroidConfiguration {
    pkgs = import inputs.nixpkgs { system = "aarch64-linux"; };
    modules = [ ./nix-on-droid.nix ];
    extraSpecialArgs = { inherit flake inputs hostName; };
  };
}
```

This gets *discovered* as a custom host, but the built-in `hosts` module
doesn't know the `"nix-on-droid"` class — it only maps `"nixos"` and
`"nix-darwin"` to output keys.

#### Step 2: Replace the hosts module

Use `extraModules` to replace the built-in `hosts` module with one that
also handles the `"nix-on-droid"` class:

```nix
# nix/modules/hosts-with-droid.nix
{ types, ... }:
let
  # Extended class map
  classMap = {
    "nixos"        = "nixosConfigurations";
    "nix-darwin"   = "darwinConfigurations";
    "nix-on-droid" = "nixOnDroidConfigurations";
  };
in
{
  name = "hosts";   # same name — replaces the built-in hosts module

  options = {
    discovered  = { type = types.attrs; default = {}; };
    flakeInputs = { type = types.attrs; default = {}; };
    self        = { type = types.any;   default = null; };
  };

  impl = { options, ... }:
    let
      inherit (options) flakeInputs self;
      allInputs   = flakeInputs // (if self != null then { inherit self; } else {});
      specialArgs = { flake = self; inputs = allInputs; };

      loadHost = hostName: hostInfo:
        if hostInfo.type == "custom" then
          import hostInfo.configPath {
            inherit (specialArgs) flake inputs;
            inherit hostName;
          }
        else if hostInfo.type == "nixos" then {
          class = "nixos";
          value = flakeInputs.nixpkgs.lib.nixosSystem {
            modules     = [ hostInfo.configPath ];
            specialArgs = specialArgs // { inherit hostName; };
          };
        }
        else if hostInfo.type == "darwin" then {
          class = "nix-darwin";
          value = (flakeInputs.nix-darwin or (throw "missing inputs.nix-darwin"))
            .lib.darwinSystem {
              modules     = [ hostInfo.configPath ];
              specialArgs = specialArgs // { inherit hostName; };
            };
        }
        else throw "unknown host type '${hostInfo.type}' for '${hostName}'";

      loaded = builtins.mapAttrs loadHost options.discovered;

      mkCategory = category:
        builtins.listToAttrs (builtins.filter (x: x != null)
          (map (name:
            let host = loaded.${name};
            in if (classMap.${host.class} or null) == category
               then { inherit name; value = host.value; }
               else null
          ) (builtins.attrNames loaded)));
    in
    {
      nixosConfigurations       = mkCategory "nixosConfigurations";
      darwinConfigurations      = mkCategory "darwinConfigurations";
      nixOnDroidConfigurations  = mkCategory "nixOnDroidConfigurations";
    };
}
```

#### Step 3: Wire it into your flake

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixos-unstable";
    nix-on-droid.url = "github:nix-community/nix-on-droid/release-24.05";
    nix-on-droid.inputs.nixpkgs.follows = "nixpkgs";
    red-tape.url = "github:you/red-tape";
  };

  outputs = inputs:
    let
      red-tape = inputs.red-tape.lib;
    in
    red-tape {
      inherit inputs;
      extraModules = {
        # Pass adios so the module can destructure { types, ... }
        hosts = import ./nix/modules/hosts-with-droid.nix red-tape.adios;
      };
    };
}
```

Now `hosts/myphone/default.nix` is discovered, the custom module handles it,
and `nixOnDroidConfigurations.myphone` appears in the flake outputs — all
without touching red-tape's core.

### Example: a completely new output type

For outputs with no host-like structure — say, a set of system images — you
can add a brand new system-agnostic module. Its result is automatically
merged into the top-level flake outputs by `collectAgnostic`:

```nix
# A module that scans images/ and builds them
let
  redTape = import inputs.red-tape {};
  inherit (redTape._internal) discover callFile;
in
{
  name = "images";   # new name — no conflict with built-ins

  options = {
    src         = { type = types.path; };
    flakeInputs = { type = types.attrs; default = {}; };
    self        = { type = types.any;   default = null; };
  };

  impl = { options, ... }:
    let
      allInputs = options.flakeInputs
        // (if options.self != null then { self = options.self; } else {});
      scope     = { flake = options.self; inputs = allInputs; };
      imagesDir = options.src + "/images";
    in
    if !builtins.pathExists imagesDir then {}
    else {
      images = builtins.mapAttrs (name: entry:
        callFile scope
          (if entry.type == "directory" then entry.path + "/default.nix" else entry.path)
          { inherit name; }
      ) (redTape._internal.scanDir imagesDir);
    };
}
```

Wire it with `extraModules` and `config`:

```nix
outputs = inputs:
  let red-tape = inputs.red-tape.lib;
  in red-tape {
    inherit inputs;
    extraModules = {
      images = import ./nix/modules/images.nix red-tape.adios;
    };
    config = {
      images = {
        src         = ./.;
        flakeInputs = builtins.removeAttrs inputs [ "self" ];
        self        = inputs.self or null;
      };
    };
  };
```

`config` maps to adios option paths — `config.images` sets `/images` options.
The module's result (`{ images = { ... }; }`) is merged into the flake outputs
by `collectAgnostic` since `"images"` is not a known built-in module name.

### The module contract

For `collectAgnostic` to pick up a custom module result:
- Name it anything **other than** `nixpkgs`, `packages`, `devshells`,
  `formatter`, `checks`, `hosts`, `overlays`, `modules-export`
- Return a flat attrset from `impl` — it's merged directly with `//` into
  the top-level flake outputs

For per-system custom modules (results transposed across systems):
- Add `inputs.nixpkgs = { path = "/nixpkgs"; }` to the module
- Options get `extraScope` from the entry point (which includes `pkgs`, `lib`, etc.)
- Results flow through `collectPerSystem` if you handle them there, or use
  `config` to pass options and let `collectAgnostic` merge the result
