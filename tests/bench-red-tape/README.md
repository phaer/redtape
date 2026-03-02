# Performance benchmark

Equivalent projects for comparing red-tape vs blueprint evaluation time.

## Structure

Both projects have:
- 6 packages, 6 devshells, 5 checks (per-system)
- 5 NixOS host configurations (system-agnostic, all x86_64-linux)
- 5 NixOS modules, lib/default.nix (system-agnostic)
- red-tape only: 6 overlays

Evaluated across 4 systems (x86_64-linux, aarch64-linux, x86_64-darwin,
aarch64-darwin).

## Running

```console
./tests/bench.sh              # 5 iterations
./tests/bench.sh -n 10        # 10 iterations
./tests/bench.sh -n 1 -v      # 1 iteration, verbose
```

Uses `nix-eval-jobs --workers 1 --force-recurse` to force full evaluation
of all derivations — the same workload as CI.

## Results (typical)

| attribute | framework | 1-sys | 4-sys |
|-----------|-----------|-------|-------|
| packages  | red-tape  | ~330ms | ~1010ms |
| packages  | blueprint | ~315ms | ~1015ms |
| checks    | red-tape  | ~11.8s | ~17.8s |
| checks    | blueprint | ~11.7s | ~12.6s |
| devShells | red-tape  | ~520ms | ~1540ms |
| devShells | blueprint | ~530ms | ~1530ms |

### Key findings

**packages/devShells** — Identical between red-tape and blueprint. These are
purely per-system; adios memoization provides no benefit here.

**checks 1-sys** — Identical. Both now evaluate NixOS host closures as checks
(`nixos-<hostname>`), which dominates the cost.

**checks 4-sys** — Red-tape is ~40% slower. Blueprint scales from 11.7→12.6s
(+8%) while red-tape goes 11.8→17.8s (+51%). The hosts are all x86_64-linux
so 3 of 4 systems produce no host checks, but red-tape's `autoChecks` still
accesses the host module results per system (forcing `hostPlatform` evaluation
each time). Blueprint resolves this more efficiently.
