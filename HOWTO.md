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
