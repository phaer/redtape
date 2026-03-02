# builders/devshells.nix — Build devshells from discovered entries
#
# Returns: { devShells = { <name> = <drv>; ... }; }
{ callFile, withPrefix }:
{ discovered, scope }:
let
  inherit (builtins) mapAttrs;

  built = mapAttrs (pname: entry:
    let path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
    in callFile scope path { inherit pname; }
  ) discovered;

  autoChecks = withPrefix "devshell-" built;
in
{
  devShells = built;
  inherit autoChecks;
}
