#!/usr/bin/env bash
# bench/run.sh — Compare red-tape vs blueprint eval performance
# Requires: hyperfine, jq (or run via: nix-shell -p hyperfine jq --run './bench/run.sh')
#
# Usage: ./bench/run.sh [--runs N] [--warmup N]
#
# Evaluates both frameworks against tests/fixtures/full
# (3 NixOS hosts, 2 packages, 2 devshells, checks, modules, templates)
# and reports timing.

set -euo pipefail
cd "$(dirname "$0")"

RUNS=10
WARMUP=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs)   RUNS="$2"; shift 2 ;;
    --warmup) WARMUP="$2"; shift 2 ;;
    *)        echo "Usage: $0 [--runs N] [--warmup N]"; exit 1 ;;
  esac
done

echo "=== Benchmark: red-tape vs blueprint ==="
echo "Project: tests/fixtures/full (3 NixOS hosts, 2 packages, 2 devshells, checks, modules, templates)"
echo "Runs: $RUNS, Warmup: $WARMUP"
echo ""

# Show what each framework discovers
echo "--- red-tape outputs ---"
nix-instantiate --eval redtape.nix --strict 2>/dev/null \
  | sed 's/{ /{\n  /g; s/ }/\n}/g; s/; /;\n  /g'
echo ""

echo "--- blueprint outputs ---"
nix-instantiate --eval blueprint.nix --strict 2>/dev/null \
  | sed 's/{ /{\n  /g; s/ }/\n}/g; s/; /;\n  /g'
echo ""

echo "--- Timing ---"
hyperfine \
  --warmup "$WARMUP" \
  --runs "$RUNS" \
  --export-json results.json \
  'nix-instantiate --eval redtape.nix --strict' \
  'nix-instantiate --eval blueprint.nix --strict'

echo ""
echo "--- Summary ---"
jq -r '
  .results[] |
  "\(.command):\n  mean: \(.mean * 1000 | round)ms  ±\(.stddev * 1000 | round)ms\n  min:  \(.min * 1000 | round)ms\n  max:  \(.max * 1000 | round)ms"
' results.json
