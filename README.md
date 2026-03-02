# red-tape

Convention-based flake output builder on top of
[adios-flake](https://github.com/Mic92/adios-flake).
Drop `.nix` files in the right directories, get flake outputs with zero
boilerplate. ~300 lines of library code.

## Quick Start

```nix
# flake.nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.red-tape.url = "github:phaer/red-tape";

  outputs = inputs: inputs.red-tape.lib { inherit inputs; };
}
```

```
my-project/
├── flake.nix                          # ← just the above
├── package.nix                        # → packages.default + checks.pkgs-default
├── packages/widget.nix                # → packages.widget + checks.pkgs-widget
├── devshell.nix                       # → devShells.default + checks.devshell-default
├── hosts/myhost/configuration.nix     # → nixosConfigurations.myhost + checks.nixos-myhost
└── modules/nixos/server.nix           # → nixosModules.server
```

Add a file, get an output. No `forAllSystems`, no manual check wiring.

## Directory Conventions

```
your-project/
├── package.nix                → packages.default
├── packages/
│   ├── foo.nix                → packages.foo
│   └── bar/default.nix        → packages.bar
├── devshell.nix               → devShells.default
├── devshells/
│   └── backend.nix            → devShells.backend
├── formatter.nix              → formatter (fallback: nixfmt-tree)
├── checks/
│   └── lint.nix               → checks.lint
├── overlay.nix                → overlays.default
├── overlays/
│   └── my-tools.nix           → overlays.my-tools
├── hosts/
│   ├── web/
│   │   └── configuration.nix         → nixosConfigurations.web
│   ├── laptop/
│   │   └── darwin-configuration.nix  → darwinConfigurations.laptop
│   └── custom/
│       └── default.nix               → escape hatch (returns { class, value })
├── modules/
│   ├── nixos/server.nix       → nixosModules.server
│   ├── darwin/defaults.nix    → darwinModules.defaults
│   └── home/shared.nix        → homeModules.shared
├── templates/
│   └── default/               → templates.default
└── lib/default.nix            → lib
```

Every entry can be a `.nix` file or a directory with `default.nix`.
The directory form is useful for multi-file packages with local sources.

## How Files Are Called

Files under `packages/`, `devshells/`, `checks/`, and `formatter.nix` are
imported like `callPackage` — red-tape inspects the function's formal
arguments and passes only what's requested:

```nix
# packages/widget.nix
{ pkgs, lib, pname, ... }:
pkgs.stdenv.mkDerivation {
  inherit pname;
  src = ./.;
}
```

| Argument | Value |
|----------|-------|
| `pkgs` | nixpkgs for the current system |
| `lib` | `pkgs.lib` |
| `system` | e.g. `"x86_64-linux"` |
| `pname` | derived from filename (`widget.nix` → `"widget"`) |
| `flake` | `self` |
| `inputs` | all flake inputs (including `self`) |
| `perSystem` | per-system packages from all inputs (see below) |

Take only what you need. `{ pkgs, ... }:` is the common case.

### `perSystem`

Resolves `legacyPackages.<system>` and `packages.<system>` from each input,
so you don't have to thread `system` through yourself:

```nix
# devshell.nix
{ pkgs, perSystem, ... }:
pkgs.mkShell {
  packages = [ perSystem.some-tool.default ];
}
```

### Overlays

Overlay files can request `{ flake, inputs, ... }` but **not** `pkgs` or
`system` — overlays are system-agnostic:

```nix
# overlay.nix
{ ... }:
final: prev: { my-pkg = prev.something.overrideAttrs { ... }; }
```

## Auto-Checks

Packages, devshells, and hosts automatically become checks:

| Source | Check name |
|--------|------------|
| `packages.foo` | `checks.pkgs-foo` |
| `packages.foo.passthru.tests.bar` | `checks.pkgs-foo-bar` |
| `devShells.default` | `checks.devshell-default` |
| `nixosConfigurations.web` | `checks.nixos-web` |
| `darwinConfigurations.laptop` | `checks.darwin-laptop` |

Host checks build `system.build.toplevel` and land under the host's
native `nixpkgs.hostPlatform`. User-defined checks in `checks/` take
precedence over auto-generated ones.

## Hosts

### NixOS

```nix
# hosts/web/configuration.nix
{ config, pkgs, flake, inputs, hostName, ... }:
{
  networking.hostName = hostName;  # "web"
}
```

red-tape calls `nixpkgs.lib.nixosSystem`, passing
`{ flake, inputs, hostName }` as `specialArgs`.

### Darwin

```nix
# hosts/laptop/darwin-configuration.nix
{ config, pkgs, flake, inputs, hostName, ... }:
{ }
```

Requires `inputs.nix-darwin`.

### Custom escape hatch

```nix
# hosts/special/default.nix
{ flake, inputs, hostName }:
{
  class = "nixos";  # or "nix-darwin"
  value = inputs.nixpkgs.lib.nixosSystem { /* full control */ };
}
```

## Modules

Files under `modules/<type>/` are re-exported as flake outputs:

| Directory | Output |
|-----------|--------|
| `modules/nixos/` | `nixosModules` |
| `modules/darwin/` | `darwinModules` |
| `modules/home/` | `homeModules` |

### Publisher args

If a module needs to reference the flake where it's *defined* (not where
it's consumed), wrap it in a function taking `{ flake, inputs }`:

```nix
# modules/nixos/myapp.nix
{ flake, inputs }:    # ← called once at export time
{ config, lib, ... }: # ← the NixOS module, evaluated per consumer
{
  options.services.myapp.package = lib.mkOption {
    default = flake.packages.${config.nixpkgs.hostPlatform.system}.default;
  };
}
```

The original file path is preserved in NixOS module error messages.

### Custom module types

Register new module directories via `moduleTypeAliases`:

```nix
inputs.red-tape.lib {
  inherit inputs;
  moduleTypeAliases = { flake = "flakeModules"; };
  # modules/flake/foo.nix → flakeModules.foo
};
```

## Configuration

```nix
inputs.red-tape.lib {
  inherit inputs;

  # Monorepo: scan from a subdirectory
  prefix = "nix";

  # Target systems (default: x86_64-linux, aarch64-linux, aarch64-darwin, x86_64-darwin)
  systems = [ "x86_64-linux" "aarch64-darwin" ];

  # Custom nixpkgs configuration
  nixpkgs = {
    config.allowUnfree = true;
    overlays = [ my-overlay ];
  };

  # Additional module type aliases
  moduleTypeAliases = { flake = "flakeModules"; };

  # Extra per-system outputs (merged with discovery, user takes precedence)
  perSystem = { pkgs, system, ... }: {
    packages.special = pkgs.callPackage ./special.nix {};
  };

  # Extra system-agnostic outputs
  flake = {
    nixosConfigurations.extra = { /* ... */ };
  };

  # Or use withSystem for system-agnostic outputs that need per-system access
  flake = { withSystem }: {
    nixosConfigurations.extra = withSystem "x86_64-linux" (
      { pkgs, ... }: { /* ... */ }
    );
  };

  # adios-flake modules for extension (see below)
  modules = [ ];

  # adios-flake config
  config = {};
}
```

## Extension

red-tape is built on [adios-flake](https://github.com/Mic92/adios-flake).
New host types and output types are added via standard adios-flake modules
passed through the `modules` parameter — no custom plugin protocol.

### Primitives

The `_internal` API exposes the building blocks:

| Primitive | Description |
|-----------|-------------|
| `discover.scanDir` | Scan a directory for `.nix` files and `*/default.nix` subdirs |
| `discover.scanHosts` | Scan host dirs for sentinel files (`[{ type; file; }]`) |
| `discover.discoverAll` | Full-tree scan using all conventions |
| `callFile` | Import + auto-inject from scope |
| `buildAll` | `callFile` over every discovered entry |
| `entryPath` | Resolve entry to `.nix` path |
| `withPrefix` | Prefix all keys in an attrset |
| `filterPlatforms` | Keep derivations matching `meta.platforms` |

### Example: nix-on-droid support

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-on-droid.url = "github:nix-community/nix-on-droid";
    red-tape.url = "github:phaer/red-tape";
  };

  outputs = inputs:
    let rt = inputs.red-tape.lib;
    in rt {
      inherit inputs;
      modules = [
        ({ self, ... }:
          let
            discovered = rt._internal.discover.scanHosts (inputs.self + "/hosts") [
              { type = "nix-on-droid"; file = "droid-configuration.nix"; }
            ];
          in {
            nixOnDroidConfigurations = builtins.mapAttrs (hostName: info:
              inputs.nix-on-droid.lib.nixOnDroidConfiguration {
                pkgs = import inputs.nixpkgs { system = "aarch64-linux"; };
                modules = [ info.configPath ];
                extraSpecialArgs = { flake = self; inherit hostName; };
              }
            ) discovered;
          }
        )
      ];
    };
}
```

A pre-built module for [system-manager](https://github.com/numtide/system-manager)
is available in [`contrib/system-manager.nix`](contrib/).

## Architecture

```
flake.nix           — entry point, __functor wrapper
nix/
  default.nix       — primitives, builders, mkFlake  (225 lines)
  discover.nix      — pure filesystem scanning        (79 lines)
```

**Five primitives** — `callFile`, `entryPath`, `buildAll`, `withPrefix`,
`filterPlatforms` — compose to handle all per-system output types.
Two domain-specific builders handle modules (publisher args, type aliases)
and hosts (sentinel dispatch, auto-checks).

**Discovery** is pure: `builtins.readDir` + `builtins.pathExists`, no
evaluation. The result is an attrset of `{}` (nothing found) or
`{ name = { path; type; }; ... }` entries — the same shape that `buildAll`
consumes directly.

**adios-flake** handles per-system transposition, memoization, module
composition, `self'`/`inputs'`/`withSystem`. red-tape is just the convention
layer on top.

## Comparison with blueprint

[blueprint](https://github.com/numtide/blueprint) is the closest relative —
nearly identical directory conventions. Migration is a one-line `flake.nix`
change.

| | blueprint | red-tape |
|-|-----------|----------|
| Overlays | ✗ | ✓ |
| Formatter fallback | needs `formatter.nix` | `nixfmt-tree` default |
| TOML devshells | ✓ | ✗ |
| Home-manager users under hosts | ✓ | ✗ |
| Custom module types | ✗ | ✓ (`moduleTypeAliases`) |
| Extension mechanism | — | adios-flake modules |
| Publisher args | ✓ | ✓ |
| Memoization | ✗ | adios (system-agnostic work shared) |

## Comparison with flake-parts

[flake-parts](https://github.com/hercules-ci/flake-parts) is a module
system for *configuring* outputs. red-tape is file conventions — write the
`.nix` file and the output appears.

| | flake-parts | red-tape |
|-|-------------|----------|
| Approach | module system configuration | filesystem conventions |
| Module system | NixOS modules (`lib.evalModules`) | adios-flake |
| Per-system eval | full module tree per system | adios memoization |
| Ecosystem | large (treefmt, devenv, hercules-ci, …) | minimal core + contrib |
| Boilerplate | moderate (still wire packages/checks) | zero (add file → get output) |

## License

MIT
