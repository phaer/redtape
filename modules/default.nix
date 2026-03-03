# red-tape — Composable adios module tree
#
# Each sub-module handles one concern. The top-level module aggregates
# results so adios-flake's _collector/_flake can route them.
let
  strip = m: builtins.removeAttrs m [ "name" ];
in
{
  default = {
    name = "red-tape";
    inputs = {
      packages = {
        path = "./packages";
      };
    };
    impl =
      { results, ... }:
      builtins.foldl' (acc: r: acc // (builtins.removeAttrs r [ "autoChecks" ])) { } (
        builtins.attrValues results
      );
    modules = {
      scan = strip (import ./scan.nix { discover = import ../lib/discover.nix; });
      scope = strip (import ./scope.nix);
      packages = strip (import ./packages.nix);
    };
  };
}
