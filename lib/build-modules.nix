# build-modules.nix — Export discovered modules
#
# Returns: { modules, nixosModules, darwinModules, homeModules }
#
# Supports publisher-args injection: if a module file is a function
# accepting { flake } and/or { inputs }, those are called before export.

{ flakeInputs, self }:

let
  inherit (builtins)
    attrNames
    functionArgs
    intersectAttrs
    isFunction
    mapAttrs
    ;

  publisherArgs = {
    flake = self;
    inputs = flakeInputs // (if self != null then { self = self; } else {});
  };

  # Check if a value is a function that only takes publisher args
  expectsPublisherArgs = fn:
    isFunction fn
    && builtins.all (arg: builtins.elem arg (attrNames publisherArgs))
      (attrNames (functionArgs fn));

  # Import a module path, injecting publisher args if needed
  importModule = entry:
    let
      path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
      mod = import path;
    in
    if expectsPublisherArgs mod then
      mod (intersectAttrs (functionArgs mod) publisherArgs)
    else
      path;

  # Well-known type aliases
  typeAliases = {
    nixos = "nixosModules";
    darwin = "darwinModules";
    home = "homeModules";
  };

in
discoveredModules:
let
  # modules.<type>.<name> = imported module
  modules = mapAttrs (_type: entries:
    mapAttrs (_name: importModule) entries
  ) discoveredModules;

  # Well-known aliases at the top level
  aliases = builtins.foldl' (acc: typeName:
    let alias = typeAliases.${typeName} or null;
    in if alias != null && discoveredModules ? ${typeName}
       then acc // { ${alias} = modules.${typeName}; }
       else acc
  ) {} (attrNames discoveredModules);
in
{ inherit modules; } // aliases
