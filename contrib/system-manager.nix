# contrib/system-manager.nix — system-manager host support as an adios-flake module
#
# Scans hosts/ for system-configuration.nix files and produces
# systemConfigs.<hostname> outputs.
#
# Usage:
#   modules = [
#     (import (red-tape + "/contrib/system-manager.nix") {
#       inherit inputs;
#       src = inputs.self;
#     })
#   ];

{ inputs, src }:
let
  discover = import ../nix/discover.nix;
  discovered = discover.scanHosts (src + "/hosts") [
    { type = "system-manager"; file = "system-configuration.nix"; }
  ];
in
{ self, ... }:
let
  flakeInputs = builtins.removeAttrs inputs [ "self" ];
  allInputs   = flakeInputs // (if self != null then { inherit self; } else {});
  specialArgs = { flake = self; inputs = allInputs; };
  system-manager = flakeInputs.system-manager
    or (throw "red-tape: system-manager contrib module needs inputs.system-manager");
in
{
  systemConfigs = builtins.mapAttrs (hostName: hostInfo:
    builtins.addErrorContext "while building system-manager host '${hostName}'" (
      system-manager.lib.makeSystemConfig {
        modules     = [ hostInfo.configPath ];
        specialArgs = specialArgs // { inherit hostName; };
      }
    )
  ) discovered;
}
