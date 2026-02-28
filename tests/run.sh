#!/usr/bin/env bash
# Run all red-tape tests using nix-unit
set -euo pipefail

cd "$(dirname "$0")/.."

for f in tests/*.nix; do
  [[ "$(basename "$f")" == "prelude.nix" ]] && continue
  echo "=== $f ==="
  nix-unit "$f"
done

echo ""
echo "All tests passed!"
