# builders/modules-export.nix — Re-export NixOS/Darwin/Home modules
#
# Returns: { nixosModules = { ... }; darwinModules = { ... }; homeModules = { ... }; }
#
# Modules under modules/<type>/ are re-exported.  If a module file is a
# function that accepts only { flake, inputs }, it's called with publisher
# args at export time (allowing the module to close over the flake).
# Otherwise the raw path is exported.
{ discovered, flakeInputs, self }:
let
  inherit (builtins) all attrNames elem foldl' functionArgs isFunction intersectAttrs mapAttrs;

  allInputs     = flakeInputs // (if self != null then { inherit self; } else {});
  publisherArgs = { flake = self; inputs = allInputs; };

  typeAliases = { nixos = "nixosModules"; darwin = "darwinModules"; home = "homeModules"; };

  expectsPublisherArgs = fn:
    isFunction fn && (functionArgs fn) != {}
    && all (arg: elem arg (attrNames publisherArgs)) (attrNames (functionArgs fn));

  importModule = entry:
    let
      path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
      mod  = import path;
    in
    if expectsPublisherArgs mod
    then mod (intersectAttrs (functionArgs mod) publisherArgs)
    else path;

  allModules = mapAttrs (_: entries: mapAttrs (_: importModule) entries) discovered;

  result = foldl' (acc: typeName:
    let alias = typeAliases.${typeName} or null;
    in if alias != null && discovered ? ${typeName}
      then acc // { ${alias} = allModules.${typeName}; }
      else acc
  ) {} (attrNames discovered);
in
result
