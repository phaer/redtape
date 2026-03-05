# red-tape

> ⚠️ **LLM-assisted.** I used an LLM for prototyping and iteration, but
> reviewed and shaped each commit myself — I don't think it meaningfully
> affected the error rate compared to writing it without. The broader social
> and economic consequences of the "AI" craze are something I'm happy to
> discuss, but this is not the place.

Convention-based Nix project builder, based on [adios-flake](https://github.com/Mic92/adios-flake) and inspired by [blueprint](https://github.com/numtide/blueprint).

Drop your Nix files in the right places, and red-tape turns them into a complete flake — packages, devshells, checks, NixOS hosts, modules, templates, and lib — with zero boilerplate.

## Quick Start

```nix
{
  inputs = {
    red-tape.url = "github:phaer/red-tape";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs = inputs:
    inputs.red-tape.mkFlake {
      inherit inputs;
      src = ./.;
    };
}
```

Then just add files following the conventions below.

## Filesystem Conventions

```
.
├── package.nix                       # → packages.${system}.default
├── packages/
│   ├── hello.nix                     # → packages.${system}.hello
│   └── goodbye/default.nix           # → packages.${system}.goodbye
├── devshell.nix                      # → devShells.${system}.default
├── devshells/
│   └── backend.nix                   # → devShells.${system}.backend
├── formatter.nix                     # → formatter.${system}
├── checks/
│   └── mycheck.nix                   # → checks.${system}.mycheck
├── hosts/
│   ├── myhost/configuration.nix      # → nixosConfigurations.myhost
│   └── custom/default.nix            # → nixosConfigurations.custom (custom builder)
├── modules/
│   └── nixos/
│       ├── server.nix                # → nixosModules.server
│       └── injected.nix              # → nixosModules.injected
├── templates/
│   ├── default/flake.nix             # → templates.default
│   └── minimal/flake.nix             # → templates.minimal
└── lib/default.nix                   # → lib (re-exported as flake output)
```

All package/devshell/check/formatter files receive `{ pkgs, lib, system, flake, inputs, perSystem, ... }`.

### Prefix

If you keep Nix files in a subdirectory (e.g. `nix/`), pass `prefix = "nix"` to `mkFlake`.

## `mkFlake` API

```nix
red-tape.mkFlake {
  # Required
  inputs = { ... };           # Flake inputs
  src = ./.;                  # Project root to scan

  # Optional
  self = null;                # Flake self-reference (optional)
  prefix = null;              # Subdirectory prefix (e.g. "nix")
  systems = [ ... ];          # Target systems (default: x86_64-linux, aarch64-linux, aarch64-darwin, x86_64-darwin)
  modules = [];               # Additional adios modules
  perSystem = null;           # Per-system function (adios-flake passthrough)
  config = {};                # Extra adios config paths
  flake = {};                 # Extra raw flake outputs
}
```

## Auto-Checks

red-tape automatically adds packages and devshells to `checks`:

- Each package becomes `checks.${system}.pkgs-${name}`
- Each devshell becomes `checks.${system}.devshell-${name}`
- Each package's `passthru.tests` are included as `checks.${system}.pkgs-${name}-${test}`

Run all checks with:

```sh
nix flake check -L
```

## Host Types

By default, red-tape supports two host types:

| File in `hosts/${name}/` | Type | Output Key |
|---|---|---|
| `configuration.nix` | `nixos` | `nixosConfigurations` |
| `default.nix` | `custom` | `nixosConfigurations` |

Custom hosts (`default.nix`) receive `{ flake, inputs, hostName }` and can return anything.

### Adding Host Types via Contrib

```nix
# In your flake.nix
red-tape.mkFlake {
  inherit inputs;
  src = ./.;
  modules = [
    (import "${inputs.red-tape}/contrib/darwin.nix")
    (import "${inputs.red-tape}/contrib/home-manager.nix")
    (import "${inputs.red-tape}/contrib/system-manager.nix")
  ];
};
```

This adds:
- `darwin-configuration.nix` → `darwinConfigurations` + `modules/darwin/` → `darwinModules` (via nix-darwin)
- `home-configuration.nix` → `homeConfigurations` + `modules/home/` → `homeModules` (via home-manager)
- `system-configuration.nix` → `systemConfigs` (via system-manager)

## Module Types

By default, only `modules/nixos/` → `nixosModules` is wired. Contrib modules add more:

```nix
red-tape.mkFlake {
  inherit inputs;
  src = ./.;
  modules = [
    (import "${inputs.red-tape}/contrib/darwin.nix")       # modules/darwin/ → darwinModules
    (import "${inputs.red-tape}/contrib/home-manager.nix") # modules/home/  → homeModules
  ];
};
```

Or define custom types via `config`:

```nix
red-tape.mkFlake {
  inherit inputs;
  src = ./.;
  config = {
    "red-tape/modules" = {
      moduleTypes = { flake = "flakeModules"; };
    };
  };
};
```

## Available Contrib Modules

| Module | What it does |
|---|---|
| `contrib/darwin.nix` | `darwin` host type → `darwinConfigurations`, `modules/darwin/` → `darwinModules` |
| `contrib/home-manager.nix` | `home-manager` host type → `homeConfigurations`, `modules/home/` → `homeModules` |
| `contrib/system-manager.nix` | `system-manager` host type → `systemConfigs` |

## Comparison

| | red-tape | blueprint | flake-parts |
|---|---|---|---|
| Approach | Filesystem conventions | Filesystem conventions | Module options |
| Built on | [adios-flake](https://github.com/Mic92/adios-flake) | None (pure functions) | NixOS module system |
| Community | New & small | Medium | Large |
| Extensible | [adios](https://github.com/adisbladis/adios) modules | No | NixOS modules |

## License

MIT
