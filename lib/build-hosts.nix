# build-hosts.nix — Build host configurations from discovered hosts
#
# Returns: { nixosConfigurations, darwinConfigurations }
#
# Host configs receive { flake, inputs, hostName } via specialArgs.
# custom hosts (default.nix) are an escape hatch — they return
# { class, value } and are classified by class.

{ flakeInputs, self }:

let
  inherit (builtins)
    attrNames
    filter
    listToAttrs
    mapAttrs
    ;

  allInputs = flakeInputs // (if self != null then { self = self; } else {});

  specialArgs = {
    flake = self;
    inputs = allInputs;
  };

  loadHost = hostName: hostInfo:
    if hostInfo.type == "custom" then
      import hostInfo.configPath {
        inherit (specialArgs) flake inputs;
        inherit hostName;
      }
    else if hostInfo.type == "nixos" then {
      class = "nixos";
      value = flakeInputs.nixpkgs.lib.nixosSystem {
        modules = [ hostInfo.configPath ];
        specialArgs = specialArgs // { inherit hostName; };
      };
    }
    else if hostInfo.type == "darwin" then
      let
        nix-darwin = flakeInputs.nix-darwin
          or (throw "red-tape: host '${hostName}' uses darwin-configuration.nix but inputs.nix-darwin is missing");
      in {
        class = "nix-darwin";
        value = nix-darwin.lib.darwinSystem {
          modules = [ hostInfo.configPath ];
          specialArgs = specialArgs // { inherit hostName; };
        };
      }
    else
      throw "red-tape: unknown host config type '${hostInfo.type}' for '${hostName}'";

  classMap = {
    "nixos" = "nixosConfigurations";
    "nix-darwin" = "darwinConfigurations";
  };

in
discoveredHosts:
let
  loaded = mapAttrs loadHost discoveredHosts;

  mkCategory = category:
    listToAttrs (filter (x: x != null)
      (map (name:
        let host = loaded.${name};
        in
        if (classMap.${host.class} or null) == category then
          { inherit name; value = host.value; }
        else
          null
      ) (attrNames loaded)));
in
{
  nixosConfigurations = mkCategory "nixosConfigurations";
  darwinConfigurations = mkCategory "darwinConfigurations";
}
