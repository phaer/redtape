# red-tape — Convention-based Nix project builder on adios-flake
#
# Exports:
#   modules.default — full adios module tree
#   mkFlake { inputs; ... } — convenience wrapper
{ adios-flake }:
let
  adiosFlakeLib = adios-flake.lib or adios-flake;
  helpers = import ./helpers.nix;
  builders = import ./builders.nix;

  modules = import ./modules (helpers // builders);

  mkFlake =
    { inputs
    , self ? inputs.self or null
    , src ? self
    , prefix ? null
    , systems ? [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ]
    , nixpkgs ? {}
    , extraModules ? []
    , perSystem ? null
    , config ? {}
    , flake ? {}
    , moduleTypeAliases ? {}
    }:
    adiosFlakeLib.mkFlake {
      inherit inputs self systems perSystem flake;
      modules = [ modules.default ] ++ extraModules;
      config = {
        "/red-tape/scan" = { inherit src self; inputs = inputs; }
          // (if prefix != null then { inherit prefix; } else {});
      }
      // (if moduleTypeAliases != {} then {
        "/red-tape/modules" = { inherit moduleTypeAliases; };
      } else {})
      // config;
    };

in { inherit mkFlake modules; }
