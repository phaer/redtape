# builders/hosts.nix — Build host configurations from discovered entries
#
# Returns: { nixosConfigurations = { ... }; darwinConfigurations = { ... }; }
{ withPrefix }:
{ discovered, flakeInputs, self }:
let
  inherit (builtins) addErrorContext attrNames filter listToAttrs map mapAttrs;

  allInputs   = flakeInputs // (if self != null then { inherit self; } else {});
  specialArgs = { flake = self; inputs = allInputs; };

  classMap = {
    "nixos"      = "nixosConfigurations";
    "nix-darwin" = "darwinConfigurations";
  };

  loadHost = hostName: hostInfo:
    addErrorContext "while building host '${hostName}' (${hostInfo.type})" (
      if hostInfo.type == "custom" then
        import hostInfo.configPath {
          inherit (specialArgs) flake inputs;
          inherit hostName;
        }
      else if hostInfo.type == "nixos" then {
        class = "nixos";
        value = flakeInputs.nixpkgs.lib.nixosSystem {
          modules     = [ hostInfo.configPath ];
          specialArgs = specialArgs // { inherit hostName; };
        };
      }
      else if hostInfo.type == "darwin" then
        let nix-darwin = flakeInputs.nix-darwin
          or (throw "red-tape: host '${hostName}' needs inputs.nix-darwin");
        in {
          class = "nix-darwin";
          value = nix-darwin.lib.darwinSystem {
            modules     = [ hostInfo.configPath ];
            specialArgs = specialArgs // { inherit hostName; };
          };
        }
      else throw "red-tape: unknown host type '${hostInfo.type}' for '${hostName}'"
    );

  loaded = mapAttrs loadHost discovered;

  mkCategory = category:
    listToAttrs (filter (x: x != null) (map (name:
      let host = loaded.${name};
      in if (classMap.${host.class} or null) == category
        then { inherit name; value = host.value; }
        else null
    ) (attrNames loaded)));

  result = {
    nixosConfigurations  = mkCategory "nixosConfigurations";
    darwinConfigurations = mkCategory "darwinConfigurations";
  };

  # Auto-checks: build system.build.toplevel for each host on its native system
  autoChecks = system:
    let
      mkHostChecks = prefix: hosts:
        listToAttrs (filter (x: x != null) (map (name:
          let
            host = hosts.${name};
            hostSystem = host.config.nixpkgs.hostPlatform.system or null;
          in
          if hostSystem == system
          then { name = "${prefix}-${name}"; value = host.config.system.build.toplevel; }
          else null
        ) (attrNames hosts)));
    in
    mkHostChecks "nixos" result.nixosConfigurations
    // mkHostChecks "darwin" result.darwinConfigurations;
in
result // { inherit autoChecks; }
