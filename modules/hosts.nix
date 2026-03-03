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
        foldl' (
          acc: key:
          let
            hosts = byOutputKey.${key} or { };
          in
          acc
          // listToAttrs (
            filter (x: x != null) (
              map (
                n:
                let
                  s = hosts.${n}.config.nixpkgs.hostPlatform.system or null;
                in
                if s == system then
                  {
                    name = "${key}-${n}";
                    value = hosts.${n}.config.system.build.toplevel;
                  }
                else
                  null
              ) (attrNames hosts)
            )
          )
        ) { } (attrNames byOutputKey);
    in
    byOutputKey // { inherit autoChecks; };
in
{
  name = "hosts";
  inputs = {
    scan = {
      path = "../scan";
    };
  };
  options = {
    extraHostTypes = {
      type = {
        name = "attrs";
        verify = v: if isAttrs v then null else "expected attrset";
      };
      default = { };
    };
  };
  impl =
    { results, options, ... }:
    let
      inherit (results.scan) discovered self inputs;
    in
    if discovered.hosts != { } then
      buildHosts {
        discovered = discovered.hosts;
        inherit inputs self;
        extraHostTypes = options.extraHostTypes;
      }
    else
      {
        nixosConfigurations = { };
        autoChecks = _: { };
      };
}
