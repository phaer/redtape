# builders/formatter.nix — Select a formatter
#
# Returns: <drv>
{ callFile }:
{ formatterPath, scope, pkgs }:
if formatterPath != null
then callFile scope formatterPath {}
else pkgs.nixfmt-tree or pkgs.nixfmt
  or (throw "red-tape: no formatter.nix and nixfmt-tree unavailable")
