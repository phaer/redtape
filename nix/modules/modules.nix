# red-tape/modules — Discover and export NixOS/Darwin/Home modules
#
# Inputs: ../scan (discovery + flake context)
# Options: moduleTypeAliases
# Result: { nixosModules, darwinModules, homeModules, ... }
{ buildModules }:

{
  name = "modules";
  inputs = {
    scan = { path = "../scan"; };
  };
  options = {
    moduleTypeAliases = {
      type = { name = "attrs"; verify = v: if builtins.isAttrs v then null else "expected attrset"; };
      default = {};
    };
  };
  impl = { results, options, ... }:
    let
      inherit (results.scan) discovered self allInputs;
    in
    if discovered.modules != {} then
      buildModules {
        discovered = discovered.modules;
        inherit allInputs self;
        extraTypeAliases = options.moduleTypeAliases;
      }
    else
      {};
}
