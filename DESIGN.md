# red-tape — Design Notes

## Architecture Overview

```
lib/discover.nix    Pure filesystem scanning (no evaluation)
        ↓
modules/*           adios-flake modules (build logic)
        ↓
lib/default.nix     Entry point: mkFlake + module re-export
        ↓
flake.nix           Public API
```

### lib/discover.nix

Pure functions that scan the filesystem and return structured data:

- **`scanDir path`** — Reads a directory and returns `{ name = path; }` for each `.nix` file or subdirectory with `default.nix`. Strips `.nix` extensions. Renames `default` entries to the parent directory name.
- **`scanHosts hostsDir hostTypes`** — Scans `hosts/` subdirectories, matching against an ordered list of `{ type, file }` specs. First match wins.
- **`coreHostTypes`** — Built-in host type specs: `nixos` (configuration.nix), `custom` (default.nix).
- **`discoverAll src`** — Discovers all convention paths under `src` and returns `{ packages, devShells, checks, formatter, hosts, modules, templates, lib }`.

No evaluation happens here — only `builtins.readDir`, `builtins.pathExists`, and path construction.

### modules/

[adios-flake](https://github.com/phaer/adios-flake) modules that consume discovered data and build flake outputs. adios-flake is a flake-output wrapper around [adios](https://github.com/adisbladis/adios), a lightweight module system with explicit dependency declaration and topological ordering.

```
scan ──→ scope ──→ packages
              ├──→ devshells
              ├──→ formatter
              └──→ checks (also depends on packages, devshells, hosts)

scan ──→ hosts
    ├──→ modules
    ├──→ templates
    └──→ lib
```

**Per-system modules** (packages, devshells, formatter, checks) depend on `scope` which provides `{ system, pkgs, lib, flake, inputs, perSystem }`.

**System-agnostic modules** (hosts, modules, templates, lib) depend only on `scan`.

### lib/utils.nix

Shared helper functions used by multiple modules:

- **`callFile scope path`** — Calls a Nix file with the scope attrset, using `builtins.functionArgs` to determine which arguments to pass.
- **`entryPath name info`** — Extracts the filesystem path from a discovered entry.
- **`buildAll scope discovered`** — Maps `callFile` over all discovered entries.
- **`filterPlatforms system pkgs`** — Filters packages by `meta.platforms` (keeps those matching `system` or having no platform restriction).
- **`withPrefix prefix attrs`** — Prepends a string prefix to all attribute names.

## Design Decisions

### Why adios-flake?

[adios-flake](https://github.com/phaer/adios-flake) wraps [adios](https://github.com/adisbladis/adios), a lightweight module system with explicit dependency declaration and topological ordering. Each module declares its inputs (other modules it depends on) and gets their results injected. This avoids the complexity of NixOS-style module merging while still supporting composition.

### Why convention-over-configuration?

Most Nix projects follow similar patterns: packages in `packages/`, devshells in `devshells/`, etc. By scanning the filesystem, red-tape eliminates the need to manually wire each file into `flake.nix`. Adding a new package is as simple as creating a file. This approach is shared with [blueprint](https://github.com/numtide/blueprint).

### Why no overlays in core?

Overlays encourage global mutation of nixpkgs, which makes builds harder to reason about and reproduce. red-tape focuses on explicit package definitions via `callPackage`-style evaluation. Projects that need overlays can add them via `flake` passthrough.

### Why only nixosModules by default?

NixOS modules are the most common case. Darwin and home-manager modules are opt-in via contrib modules, keeping the core small and avoiding unnecessary dependencies.

## Extensibility

### Custom Host Types

Contrib modules can add host types by setting two adios-flake config paths:

1. `"/red-tape/scan".extraHostTypes` — Adds `{ type, file }` specs to the scanner
2. `"/red-tape/hosts".extraHostTypes.${type}` — Provides `{ outputKey, build }` for the builder

See `contrib/darwin.nix`, `contrib/home-manager.nix`, and `contrib/system-manager.nix` for examples.

### Custom Module Types

The `moduleTypes` option maps directory names under `modules/` to flake output keys:

```nix
{ home = "homeModules"; darwin = "darwinModules"; }
```

This can be set via contrib modules that set `"/red-tape/modules".moduleTypes`, or directly via `config` in `mkFlake`.

## Testing

Tests use [nix-unit](https://github.com/nix-community/nix-unit) and live in `tests/`:

- **Unit tests** (`scan-dir.nix`, `discover.nix`) — Test pure scanning functions against fixtures
- **Builder tests** (`integration.nix`, `hosts.nix`, `modules-export.nix`, etc.) — Test build logic with mock pkgs
- **Module tree tests** (`module.nix`) — Test the full adios-flake module tree end-to-end
- **Extensibility tests** (`extensibility.nix`) — Test custom host types and module types
- **Prefix tests** (`prefix.nix`) — Test prefix-based discovery

All tests are aggregated in `tests/default.nix` and run via `nix run nixpkgs#nix-unit -- tests/default.nix`.
