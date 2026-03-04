# red-tape/hosts — Build host configurations
let
  inherit (builtins)
    addErrorContext
    attrNames
    filter
    foldl'
    isAttrs
    listToAttrs
    map
    mapAttrs
    ;

  defaultHostTypes = {
    custom = {
      outputKey = "nixosConfigurations";
      build =
        {
          name,
          info,
          specialArgs,
          inputs,
        }:
        import info.configPath {
          inherit (specialArgs) flake inputs;
          hostName = name;
        };
    };
    nixos = {
      outputKey = "nixosConfigurations";
      build =
        {
          name,
          info,
          specialArgs,
          inputs,
        }:
        inputs.nixpkgs.lib.nixosSystem {
          modules = [ info.configPath ];
          specialArgs = specialArgs // {
            hostName = name;
          };
        };
    };
  };

  buildHosts =
    {
      discovered,
      inputs,
      self,
      extraHostTypes ? { },
    }:
    let
      specialArgs = {
        flake = self;
        inherit inputs;
      };
      hostTypes = defaultHostTypes // extraHostTypes;

      loadHost =
        name: info:
        addErrorContext "while building host '${name}' (${info.type})" (
          let
            builder = hostTypes.${info.type} or null;
          in
          if builder == null then
            throw "red-tape: unknown host type '${info.type}' for '${name}'"
          else
            {
              type = info.type;
              outputKey = builder.outputKey;
              value = builder.build {
                inherit
                  name
                  info
                  specialArgs
                  inputs
                  ;
              };
            }
        );

      loaded = mapAttrs loadHost discovered;

      byOutputKey = foldl' (
        acc: n:
        let
          h = loaded.${n};
          key = h.outputKey;
        in
        acc
        // {
          ${key} = (acc.${key} or { }) // {
            ${n} = h.value;
          };
        }
      ) { } (attrNames loaded);

      autoChecks =
        system:
        listToAttrs (
          filter (x: x != null) (
            map (
              n:
              let
                h = loaded.${n};
                s = h.value.config.nixpkgs.hostPlatform.system or null;
              in
              if s == system then
                {
                  name = "${h.type}-${n}";
                  value = h.value.config.system.build.toplevel;
                }
              else
                null
            ) (attrNames loaded)
          )
        );
    in
    byOutputKey // { inherit autoChecks; };
in
{
  name = "hosts";
  inputs = {
    scan = {
      path = "../scan";
    };
    contrib = {
      path = "../contrib";
    };
  };
  impl =
    { results, ... }:
    let
      inherit (results.scan) discovered self inputs;
    in
    if discovered.hosts != { } then
      buildHosts {
        discovered = discovered.hosts;
        inherit inputs self;
        extraHostTypes = results.contrib.hostTypes;
      }
    else
      {
        nixosConfigurations = { };
        autoChecks = _: { };
      };
}
