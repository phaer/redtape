# red-tape: Design Document

## Summary

Convention-based Nix project builder on [adios](https://github.com/adisbladis/adios).
Filesystem layout drives output generation. Adios provides memoization across
systems and explicit dependency tracking.

Supports both flakes and traditional `default.nix` (npins/niv).

---

## Architecture

```
Entry point (mk-red-tape.nix)
│
├── discover(src)                ← pure function, runs once
│   Returns paths for packages, devshells, checks, formatter,
│   hosts, modules, overlays, templates, lib
│
├── adios module tree:
│   Per-system (depend on /nixpkgs, re-evaluated per system):
│   ├── /nixpkgs    ← data-only: { system, pkgs }
│   ├── /packages   ← callPackage discovered package files
│   ├── /devshells  ← build discovered devshell files
│   ├── /formatter  ← formatter derivation (fallback nixfmt-tree)
│   └── /checks     ← user-defined checks
│
│   System-agnostic (no /nixpkgs dep, memoized across overrides):
│   ├── /hosts          ← nixosConfigurations, darwinConfigurations
│   ├── /overlays       ← nixpkgs overlays (functions, not derivations)
│   └── /modules-export ← nixosModules, darwinModules, homeModules
│
├── Plain functions (outside adios):
│   ├── build-templates ← templates with descriptions
│   └── lib export      ← lib/default.nix
│
└── Result assembly
    ← auto-checks from packages/devshells
    ← transpose per-system → flake shape
    ← merge system-agnostic outputs
```

All modules except `/nixpkgs` and `/formatter` are conditional — only
included when the corresponding directory or file is discovered. An empty
project has just nixpkgs + formatter in the tree.

### Why discovery is a plain function

In adios, `inputs` gives a dependency's **options**, not its impl results.
Discovery results must be passed as options by the entry point. Making
discovery an adios module would add complexity for no benefit — it has no
dependencies and naturally evaluates once.

### Why `self` stays outside adios

`self` (flake fixpoint) is threaded through callPackage scope and host
specialArgs. Adios never tracks it — no memoization interference, and Nix's
lazy evaluation resolves `self` references naturally.

### Multi-system memoization

First system: full eval. Subsequent systems: `override` changes `/nixpkgs`.
Adios skips re-evaluation of modules whose inputs haven't changed.
System-agnostic modules (hosts, overlays, modules-export) are evaluated
once and shared across all system overrides.

---

## Per-system outputs (adios modules)

| Convention | Output | CallPackage args |
|-----------|--------|-----------------|
| `package.nix` / `packages/` | `packages.<name>` | `{ pkgs, pname, lib, system, perSystem, flake, inputs }` |
| `devshell.nix` / `devshells/` | `devShells.<name>` | same |
| `formatter.nix` | `formatter` | same (fallback: `nixfmt-tree`) |
| `checks/` | `checks.<name>` | same |

Auto-checks assembled in entry point:
- `packages.foo` → `checks.pkgs-foo`
- `packages.foo.passthru.tests.bar` → `checks.pkgs-foo-bar`
- `devShells.default` → `checks.devshell-default`

## System-agnostic outputs (adios modules, memoized)

| Convention | Output |
|-----------|--------|
| `hosts/*/configuration.nix` | `nixosConfigurations.*` |
| `hosts/*/darwin-configuration.nix` | `darwinConfigurations.*` |
| `hosts/*/default.nix` | escape hatch (returns `{ class, value }`) |
| `overlay.nix` / `overlays/` | `overlays.*` |
| `modules/nixos/` | `nixosModules.*` |
| `modules/darwin/` | `darwinModules.*` |
| `modules/home/` | `homeModules.*` |

## System-agnostic outputs (plain functions)

| Convention | Output |
|-----------|--------|
| `templates/*/` | `templates.*` |
| `lib/default.nix` | `lib` |

## Not in scope (contrib)

- Home-manager auto-wiring
- System-manager hosts
- Raspberry Pi hosts
- TOML devshells

---

## Design Decisions

**D1. Discovery is a plain function** — no adios module overhead, results
passed as options.

**D2. `perSystem` injected at entry point** — keeps adios tree minimal;
built outside and passed via callPackage scope.

**D3. Same module tree for flake and traditional** — one code path,
traditional = single system, no transposition.

**D4. `self` outside adios graph** — threaded via callPackage scope and
host specialArgs.

**D5. Flat `config` parameter** — maps to adios tree options directly.

**D6. Minimal core** — packages, devshells, formatter, checks are per-system
adios modules. Hosts, overlays, modules-export are system-agnostic adios
modules. Templates and lib are plain functions.

**D7. Overlays are system-agnostic** — they're functions (`final: prev: {}`),
not derivations. No `/nixpkgs` dependency, evaluated once.

**D8. DRY per-system modules** — `mk-per-system-module` factory extracts
the shared scope + callFile + mapAttrs pattern.

**D9. Flake reuses npins** — `flake.nix` does `import ./. {}`, no flake
inputs. npins is the single source of truth (same pattern as adios).

---

## File Structure

```
red-tape/
├── flake.nix                    # import ./. {} + lib wrapper
├── default.nix                  # Traditional entry: { mkFlake, eval }
├── shell.nix                    # Dev shell
├── modules/
│   ├── discover.nix             # Pure function: filesystem scan
│   ├── nixpkgs.nix              # Data-only: system + pkgs
│   ├── packages.nix             # Per-system packages (conditional)
│   ├── devshells.nix            # Per-system devshells (conditional)
│   ├── formatter.nix            # Per-system formatter (always present)
│   ├── checks.nix               # Per-system checks (conditional)
│   ├── overlays.nix             # System-agnostic overlays (conditional)
│   ├── hosts.nix                # System-agnostic hosts (conditional)
│   └── modules-export.nix       # System-agnostic module export (conditional)
├── lib/
│   ├── mk-red-tape.nix          # Core: tree + result assembly
│   ├── mk-per-system-module.nix # Factory for per-system modules
│   ├── call-file.nix            # callPackage-style invocation
│   ├── scan-dir.nix             # readDir scanner
│   ├── scan-hosts.nix           # Host directory scanner
│   ├── filter-platforms.nix     # meta.platforms filter
│   ├── transpose.nix            # Per-system → flake shape
│   └── build-templates.nix      # Template export
└── tests/
    ├── prelude.nix              # Shared test setup
    ├── *.nix                    # 12 test suites, 84 tests
    ├── run.sh                   # Test runner
    └── fixtures/                # Mock project trees
```
