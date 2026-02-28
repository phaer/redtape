# red-tape: Design Document

## Summary

Convention-based Nix project builder on [adios](https://github.com/msteen/adios).
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
│   hosts, modules, templates, lib
│
├── adios module tree (per-system, overridden per system):
│   /nixpkgs    ← data-only: { system, pkgs }
│   /packages   ← callPackage discovered package files
│   /devshells  ← build discovered devshell files
│   /formatter  ← formatter derivation (fallback nixfmt-tree)
│   /checks     ← user-defined checks
│
├── System-agnostic assembly (plain functions, outside adios):
│   build-hosts     ← nixosConfigurations, darwinConfigurations
│   build-modules   ← nixosModules, darwinModules, homeModules
│   build-templates ← templates with descriptions
│   lib export      ← lib/default.nix
│
└── Result assembly
    ← auto-checks from packages/devshells
    ← transpose per-system → flake shape
    ← merge system-agnostic outputs
```

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

First system: full `eval`. Subsequent systems: `override` changes `/nixpkgs`.
Adios skips re-evaluation of modules whose inputs haven't changed. Currently
all per-system modules depend on `/nixpkgs`, so the benefit is limited. Future
system-agnostic adios modules (if added) would benefit more.

---

## Core (always active)

Per-system outputs through adios modules:

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

## Auto-discovered (if present)

System-agnostic, assembled outside adios:

| Convention | Output |
|-----------|--------|
| `hosts/*/configuration.nix` | `nixosConfigurations.*` |
| `hosts/*/darwin-configuration.nix` | `darwinConfigurations.*` |
| `hosts/*/default.nix` | escape hatch (returns `{ class, value }`) |
| `modules/nixos/` | `nixosModules.*` |
| `modules/darwin/` | `darwinModules.*` |
| `modules/home/` | `homeModules.*` |
| `templates/*/` | `templates.*` |
| `lib/default.nix` | `lib` |

## Not in scope (contrib)

- Home-manager auto-wiring
- System-manager hosts
- Raspberry Pi hosts
- TOML devshells
- adios-contrib compatibility

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

**D6. Minimal core** — per-system packages/devshells/formatter/checks only.
Hosts, modules, templates, lib are auto-discovered but implemented as plain
functions, not adios modules.

---

## File Structure

```
red-tape/
├── flake.nix               # Flake entry point
├── default.nix             # Traditional entry point
├── shell.nix               # Dev shell
├── modules/
│   ├── nixpkgs.nix         # Data-only: system + pkgs
│   ├── discover.nix        # Pure function: filesystem scan
│   ├── packages.nix        # Per-system package builder (conditional)
│   ├── devshells.nix       # Per-system devshell builder (conditional)
│   ├── formatter.nix       # Per-system formatter (always present)
│   └── checks.nix          # Per-system user checks (conditional)
├── lib/
│   ├── mk-red-tape.nix     # Core: tree + result assembly
│   ├── call-file.nix       # Shared callPackage-style invocation
│   ├── scan-dir.nix        # readDir scanner
│   ├── scan-hosts.nix      # Host directory scanner
│   ├── filter-platforms.nix # meta.platforms filter
│   ├── transpose.nix       # Per-system → flake shape
│   ├── build-hosts.nix     # Host config dispatch
│   ├── build-modules.nix   # Module export (well-known aliases only)
│   └── build-templates.nix # Template export
└── tests/
    ├── prelude.nix          # Shared test setup
    ├── *.nix                # Test suites (12 files, 72 tests)
    ├── run.sh               # Test runner
    └── fixtures/            # Mock project trees
```
