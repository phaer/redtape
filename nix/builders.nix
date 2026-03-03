# Domain-specific builders for NixOS/Darwin modules and host configurations.
let
  inherit (builtins)
    addErrorContext all attrNames elem filter foldl'
    functionArgs intersectAttrs isAttrs isFunction
    listToAttrs map mapAttrs;

  helpers = import ./helpers.nix;
  inherit (helpers) entryPath;

  defaultTypeAliases = { nixos = "nixosModules"; darwin = "darwinModules"; home = "homeModules"; };

  buildModules = { discovered, allInputs, self, extraTypeAliases ? {} }:
    let
      publisherArgs = { flake = self; inputs = allInputs; };
      typeAliases = defaultTypeAliases // extraTypeAliases;

      isPublisherFn = fn:
        isFunction fn && (functionArgs fn) != {}
        && all (a: elem a [ "flake" "inputs" ]) (attrNames (functionArgs fn));

      importModule = e:
        let path = entryPath e; mod = import path;
        in if isPublisherFn mod
          then { _file = toString path; imports = [ (mod (intersectAttrs (functionArgs mod) publisherArgs)) ]; }
          else path;

      built = mapAttrs (_: mapAttrs (_: importModule)) discovered;
    in
    foldl' (acc: t:
      let alias = typeAliases.${t} or null;
      in if alias != null then acc // { ${alias} = built.${t}; } else acc
    ) {} (attrNames discovered);

  buildHosts = { discovered, allInputs, self }:
    let
      specialArgs = { flake = self; inputs = allInputs; };
      outputKey = { nixos = "nixosConfigurations"; nix-darwin = "darwinConfigurations"; };

      loadHost = name: info:
        addErrorContext "while building host '${name}' (${info.type})" (
          if info.type == "custom" then
            import info.configPath { inherit (specialArgs) flake inputs; hostName = name; }
          else if info.type == "nixos" then {
            class = "nixos";
            value = allInputs.nixpkgs.lib.nixosSystem {
              modules = [ info.configPath ];
              specialArgs = specialArgs // { hostName = name; };
            };
          }
          else if info.type == "darwin" then
            let nd = allInputs.nix-darwin or (throw "red-tape: host '${name}' needs inputs.nix-darwin");
            in { class = "nix-darwin"; value = nd.lib.darwinSystem {
              modules = [ info.configPath ];
              specialArgs = specialArgs // { hostName = name; };
            }; }
          else throw "red-tape: unknown host type '${info.type}' for '${name}'"
        );

      loaded = mapAttrs loadHost discovered;

      byClass = cls: listToAttrs (filter (x: x != null) (map (n:
        let h = loaded.${n};
        in if (outputKey.${h.class} or null) == cls then { name = n; value = h.value; } else null
      ) (attrNames loaded)));

      nixos  = byClass "nixosConfigurations";
      darwin = byClass "darwinConfigurations";

      autoChecks = system:
        let check = pre: hosts: listToAttrs (filter (x: x != null) (map (n:
              let s = hosts.${n}.config.nixpkgs.hostPlatform.system or null;
              in if s == system then { name = "${pre}-${n}"; value = hosts.${n}.config.system.build.toplevel; } else null
            ) (attrNames hosts)));
        in check "nixos" nixos // check "darwin" darwin;
    in
    { nixosConfigurations = nixos; darwinConfigurations = darwin; inherit autoChecks; };

in { inherit buildModules buildHosts; }
