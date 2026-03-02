# contrib/system-manager.nix — system-manager host support as an adios-flake module
#
# Scans hosts/ for system-configuration.nix files and produces
# systemConfigs.<hostname> outputs. Independent from the core hosts builder —
# both run over the same hosts/ directory scanning for different sentinel files.
#
# Usage:
#   outputs = inputs:
#     let rt = inputs.red-tape.lib;
#     in rt {
#       inherit inputs;
#       modules = [
#         (import (inputs.red-tape + "/contrib/system-manager.nix") {
#           inherit inputs;
#           src = inputs.self;
#           scanHosts = rt._internal.discover.scanHosts;
#         })
#       ];
#     };

{ inputs, src, scanHosts }:
let
  inherit (builtins) addErrorContext attrNames filter listToAttrs mapAttrs;

  discovered = scanHosts (src + "/hosts") [
    { type = "system-manager"; file = "system-configuration.nix"; }
  ];
in
# Return an adios-flake ergonomic function module (system-independent)
{ self, ... }:
let
  flakeInputs = builtins.removeAttrs inputs [ "self" ];
  allInputs   = flakeInputs // (if self != null then { inherit self; } else {});
  specialArgs = { flake = self; inputs = allInputs; };

  system-manager = flakeInputs.system-manager
    or (throw "red-tape: system-manager contrib module needs inputs.system-manager");
in
{
  systemConfigs = mapAttrs (hostName: hostInfo:
    addErrorContext "while building system-manager host '${hostName}'" (
      system-manager.lib.makeSystemConfig {
        modules     = [ hostInfo.configPath ];
        specialArgs = specialArgs // { inherit hostName; };
      }
    )
  ) discovered;
}
