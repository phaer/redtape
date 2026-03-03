# red-tape — Composable adios module tree
#
# Each sub-module handles one concern. The top-level module aggregates
# results so adios-flake's _collector/_flake can route them.
{ callFile, buildAll, filterPlatforms, withPrefix
, buildModules, buildHosts, ...
}:

let
  strip = m: builtins.removeAttrs m [ "name" ];
in
{
  default = {
    name = "red-tape";
    inputs = {
      packages  = { path = "./packages"; };
      devshells = { path = "./devshells"; };
      checks    = { path = "./checks"; };
      formatter = { path = "./formatter"; };
      hosts     = { path = "./hosts"; };
      modules   = { path = "./modules"; };
      overlays  = { path = "./overlays"; };
      templates = { path = "./templates"; };
      lib       = { path = "./lib"; };
    };
    impl = { results, ... }:
      builtins.foldl' (acc: r:
        acc // (builtins.removeAttrs r [ "autoChecks" ])
      ) {} (builtins.attrValues results);
    modules = {
      scan      = strip (import ./scan.nix { discover = import ../discover.nix; });
      scope     = strip (import ./scope.nix);
      packages  = strip (import ./packages.nix { inherit buildAll filterPlatforms; });
      devshells = strip (import ./devshells.nix { inherit buildAll; });
      checks    = strip (import ./checks.nix { inherit buildAll filterPlatforms withPrefix; });
      formatter = strip (import ./formatter.nix { inherit callFile; });
      hosts     = strip (import ./hosts.nix { inherit buildHosts; });
      modules   = strip (import ./modules.nix { inherit buildModules; });
      overlays  = strip (import ./overlays.nix { inherit buildAll; });
      templates = strip (import ./templates.nix);
      lib       = strip (import ./lib.nix);
    };
  };
}
