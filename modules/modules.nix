# red-tape/modules — Discover and export NixOS/Darwin/Home modules
let
  inherit (import ../lib/utils.nix) entryPath;
  inherit (builtins)
    all
    attrNames
    elem
    foldl'
    functionArgs
    intersectAttrs
    isFunction
    mapAttrs
    ;

  defaultModuleTypes = {
    nixos = "nixosModules";
  };

  buildModules =
    {
      discovered,
      inputs,
      self,
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
in
{
  name = "modules";
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
    if discovered.modules != { } then
      buildModules {
        discovered = discovered.modules;
        inherit inputs self;
        extraModuleTypes = results.contrib.moduleTypes;
      }
    else
      { };
}
