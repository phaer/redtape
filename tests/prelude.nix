# Test prelude — shared setup for all test files
let
  discover = import ../lib/discover.nix;

  lib = { };

  mockPkgs = {
    system = "x86_64-linux";
    inherit lib;
    mkShell = args: { type = "devshell"; } // args;
    hello = {
      type = "derivation";
      name = "hello";
      meta = { };
    };
    jq = {
      type = "derivation";
      name = "jq";
      meta = { };
    };
    writeShellScriptBin = name: text: {
      type = "derivation";
      inherit name;
      meta = { };
    };
    runCommand = name: env: cmd: {
      type = "derivation";
      inherit name;
      meta = { };
    };
    nodejs = {
      type = "derivation";
      name = "nodejs";
      meta = { };
    };
    nixfmt-tree = {
      type = "derivation";
      name = "nixfmt-tree";
      meta = { };
    };
  };

  sys = "x86_64-linux";
  fixtures = ../tests/fixtures;

  helpers = import ../lib/utils.nix;

  # Domain builders — extracted for direct testing without adios runtime
  inherit (builtins)
    addErrorContext
    all
    attrNames
    elem
    filter
    foldl'
    functionArgs
    intersectAttrs
    isAttrs
    isFunction
    listToAttrs
    map
    mapAttrs
    ;
  inherit (helpers) entryPath;

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
      inputs ? { },
      self ? null,
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
        ) { } (attrNames byOutputKey);
    in
    byOutputKey // { inherit autoChecks; };

  defaultModuleTypes = {
    nixos = "nixosModules";
  };

  buildModules =
    {
      discovered,
      inputs ? { },
      self ? null,
      extraModuleTypes ? { },
    }:
    let
      publisherArgs = {
        flake = self;
        inherit inputs;
      };
      moduleTypes = defaultModuleTypes // extraModuleTypes;
      isPublisherFn =
        fn:
        isFunction fn
        && (functionArgs fn) != { }
        && all (
          a:
          elem a [
            "flake"
            "inputs"
          ]
        ) (attrNames (functionArgs fn));
      importModule =
        e:
        let
          path = entryPath e;
          mod = import path;
        in
        if isPublisherFn mod then
          {
            _file = toString path;
            imports = [ (mod (intersectAttrs (functionArgs mod) publisherArgs)) ];
          }
        else
          path;
      built = mapAttrs (_: mapAttrs (_: importModule)) discovered;

      aliased = foldl' (
        acc: t:
        let
          alias = moduleTypes.${t} or null;
        in
        if alias != null then acc // { ${alias} = built.${t}; } else acc
      ) { } (attrNames discovered);
    in
    aliased // (if built != { } then { modules = built; } else { });

  builders = { inherit buildHosts buildModules; };
in
{
  inherit
    mockPkgs
    sys
    fixtures
    discover
    helpers
    builders
    ;
}
