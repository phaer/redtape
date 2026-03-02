# builders/modules-export.nix — Re-export NixOS/Darwin/Home modules
#
# Returns: { nixosModules = { ... }; darwinModules = { ... }; homeModules = { ... }; }
#
# Modules under modules/<type>/ are re-exported.  If a module file is a
# function that accepts only { flake, inputs }, it's called with publisher
# args at export time (allowing the module to close over the flake).
# Otherwise the raw path is exported.
#
# typeAliases maps directory names to flake output keys.
# The defaults (nixos→nixosModules, darwin→darwinModules, home→homeModules)
# can be extended by passing extraTypeAliases.
{ discovered, flakeInputs, self, extraTypeAliases ? {} }:
let
  inherit (builtins) all attrNames elem foldl' functionArgs isFunction intersectAttrs mapAttrs;

  allInputs     = flakeInputs // (if self != null then { inherit self; } else {});
  publisherArgs = { flake = self; inputs = allInputs; };

  typeAliases = {
    nixos = "nixosModules";
    darwin = "darwinModules";
    home = "homeModules";
  } // extraTypeAliases;

  expectsPublisherArgs = fn:
    isFunction fn && (functionArgs fn) != {}
    && all (arg: elem arg (attrNames publisherArgs)) (attrNames (functionArgs fn));

  # Wrap a module so the NixOS module system reports the original file path
  # in error messages.  Equivalent to lib.setDefaultModuleLocation.
  setModuleLocation = file: m: { _file = file; imports = [ m ]; };

  importModule = entry:
    let
      path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
      mod  = import path;
    in
    if expectsPublisherArgs mod
    then setModuleLocation (toString path) (mod (intersectAttrs (functionArgs mod) publisherArgs))
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
