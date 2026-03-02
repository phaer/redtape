# builders/checks.nix — Build user-defined checks from discovered entries
#
# Returns: { checks = { <name> = <drv>; ... }; }
{ callFile, filterPlatforms }:
{ discovered, scope, system }:
let
  inherit (builtins) mapAttrs;

  built = mapAttrs (pname: entry:
    let path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
    in callFile scope path { inherit pname; }
  ) discovered;
in
{
  checks = filterPlatforms system built;
}
