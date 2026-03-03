# red-tape/hosts — Build NixOS/Darwin host configurations
#
# Inputs: ../scan (discovery + flake context)
# Options: extraHostBuilders — extend or override per-type build logic
#
# Result: { nixosConfigurations, darwinConfigurations, autoChecks, ... }
#
# autoChecks is a function system → { name = toplevel; } consumed by ../checks.
# nixosConfigurations and darwinConfigurations are flake-scoped (custom types may
# add further output keys via extraHostBuilders).
#
# extraHostBuilders example:
#   extraHostBuilders.nix-on-droid = {
#     outputKey = "nixOnDroidConfigurations";
#     build = { name, info, specialArgs, allInputs }:
#       allInputs.nix-on-droid.lib.nixOnDroidConfiguration { ... };
#   };
let
  inherit (builtins)
    addErrorContext attrNames filter foldl'
    isAttrs listToAttrs map mapAttrs;

  defaultHostBuilders = {
    custom = {
      outputKey = "nixosConfigurations";
      build = { name, info, specialArgs, allInputs }:
        import info.configPath { inherit (specialArgs) flake inputs; hostName = name; };
    };
    nixos = {
      outputKey = "nixosConfigurations";
      build = { name, info, specialArgs, allInputs }:
        let sys = allInputs.nixpkgs.lib.nixosSystem {
          modules = [ info.configPath ];
          specialArgs = specialArgs // { hostName = name; };
        };
        in sys;
    };
    darwin = {
      outputKey = "darwinConfigurations";
      build = { name, info, specialArgs, allInputs }:
        let nd = allInputs.nix-darwin or (throw "red-tape: host '${name}' needs inputs.nix-darwin");
        in nd.lib.darwinSystem {
          modules = [ info.configPath ];
          specialArgs = specialArgs // { hostName = name; };
        };
    };
  };

  buildHosts = { discovered, allInputs, self, extraHostBuilders ? {} }:
    let
      specialArgs = { flake = self; inputs = allInputs; };
      hostBuilders = defaultHostBuilders // extraHostBuilders;

      loadHost = name: info:
        addErrorContext "while building host '${name}' (${info.type})" (
          let builder = hostBuilders.${info.type} or null;
          in if builder == null
            then throw "red-tape: unknown host type '${info.type}' for '${name}'"
            else {
              outputKey = builder.outputKey;
              value = builder.build { inherit name info specialArgs allInputs; };
            }
        );

      loaded = mapAttrs loadHost discovered;

      # Group by outputKey, collecting into per-key attrsets
      byOutputKey = foldl' (acc: n:
        let h = loaded.${n};
            key = h.outputKey;
        in acc // { ${key} = (acc.${key} or {}) // { ${n} = h.value; }; }
      ) {} (attrNames loaded);

      autoChecks = system:
        foldl' (acc: key:
          let hosts = byOutputKey.${key} or {};
          in acc // listToAttrs (filter (x: x != null) (map (n:
            let s = hosts.${n}.config.nixpkgs.hostPlatform.system or null;
            in if s == system then { name = "${key}-${n}"; value = hosts.${n}.config.system.build.toplevel; } else null
          ) (attrNames hosts)))
        ) {} (attrNames byOutputKey);
    in
    byOutputKey // { inherit autoChecks; };
in
{
  name = "hosts";
  inputs = {
    scan = { path = "../scan"; };
  };
  options = {
    extraHostBuilders = {
      type = { name = "attrs"; verify = v: if isAttrs v then null else "expected attrset"; };
      default = {};
    };
  };
  impl = { results, options, ... }:
    let
      inherit (results.scan) discovered self allInputs;
    in
    if discovered.hosts != {} then
      buildHosts {
        discovered = discovered.hosts;
        inherit allInputs self;
        extraHostBuilders = options.extraHostBuilders;
      }
    else
      { nixosConfigurations = {}; darwinConfigurations = {}; autoChecks = _: {}; };
}
