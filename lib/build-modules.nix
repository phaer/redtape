# build-modules.nix — Export discovered modules as flake outputs
#
# Returns: { nixosModules, darwinModules, homeModules }
# Only well-known types get top-level aliases. Other types are
# accessible via modules.<type>.<name> (not exported to flake outputs
# since there's no standard flake output for arbitrary module types).
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

  allInputs = flakeInputs // (if self != null then { self = self; } else {});

  publisherArgs = {
    flake = self;
    inputs = allInputs;
  };

  # Check if a value is a function that explicitly takes publisher args.
  # Must have at least one named arg (excludes `{ ... }:` catch-all).
  expectsPublisherArgs = fn:
    let args = functionArgs fn;
    in isFunction fn
    && args != {}
    && builtins.all (arg: builtins.elem arg (attrNames publisherArgs))
      (attrNames args);

  importModule = entry:
    let
      path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
      mod = import path;
    in
    if expectsPublisherArgs mod then
      mod (intersectAttrs (functionArgs mod) publisherArgs)
    else
      path;

  typeAliases = {
    nixos = "nixosModules";
    darwin = "darwinModules";
    home = "homeModules";
  };

in
discoveredModules:
let
  allModules = mapAttrs (_type: entries:
    mapAttrs (_name: importModule) entries
  ) discoveredModules;

  # Only emit well-known aliases as flake outputs
  aliases = builtins.foldl' (acc: typeName:
    let alias = typeAliases.${typeName} or null;
    in if alias != null && discoveredModules ? ${typeName}
       then acc // { ${alias} = allModules.${typeName}; }
       else acc
  ) {} (attrNames discoveredModules);
in
aliases
