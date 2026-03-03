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
      devshells = {
        path = "./devshells";
      };
      formatter = {
        path = "./formatter";
      };
      checks = {
        path = "./checks";
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
      devshells = strip (import ./devshells.nix);
      formatter = strip (import ./formatter.nix);
      checks = strip (import ./checks.nix);
    };
  };
}
