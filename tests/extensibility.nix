# Tests for extensibility — custom host types and module types via adios-flake modules
let
  prelude = import ./prelude.nix;
  inherit (prelude) _internal fixtures;
  inherit (_internal) discover entryPath;
  inherit (_internal.builders) buildModules;
  inherit (discover) scanDir scanHosts;
in
{
  # --- Custom host types via scanHosts ---

  testScanCustomHostType = {
    expr =
      let found = scanHosts (fixtures + "/custom-hosts/hosts") [
        { type = "nix-on-droid"; file = "droid-configuration.nix"; }
      ];
      in { names = builtins.attrNames found; type = found.myphone.type; };
    expected = { names = [ "myphone" ]; type = "nix-on-droid"; };
  };

  testCoreHostTypesIgnoreCustom = {
    expr = (discover.discoverAll (fixtures + "/custom-hosts")).hosts;
    expected = {};
  };

  testScanHostsFirstMatchWins = {
    expr =
      let found = scanHosts (fixtures + "/full/hosts") [
        { type = "custom"; file = "default.nix"; }
        { type = "nixos"; file = "configuration.nix"; }
      ];
      in { customType = found.custom.type; myhostType = found.myhost.type; };
    expected = { customType = "custom"; myhostType = "nixos"; };
  };

  # --- Custom module export types ---

  # Users can scan module subdirs with scanDir (the core primitive)
  testScanModuleSubdirs = {
    expr =
      let
        modulesPath = fixtures + "/full/modules";
        entries = builtins.readDir modulesPath;
        types = builtins.filter (n: entries.${n} == "directory") (builtins.attrNames entries);
      in builtins.sort builtins.lessThan types;
    expected = [ "darwin" "home" "nixos" ];
  };

  testUnknownTypeAliasSkipped = {
    expr = buildModules {
      discovered = { flake = scanDir (fixtures + "/full/modules/nixos"); };
      allInputs = {};
      self = null;
    };
    expected = {};
  };

  testExtraTypeAliases = {
    expr =
      let result = buildModules {
        discovered = (discover.discoverAll (fixtures + "/custom-modules")).modules;
        allInputs = {};
        self = null;
        extraTypeAliases = { flake = "flakeModules"; };
      };
      in { keys = builtins.attrNames result; modNames = builtins.attrNames (result.flakeModules or {}); };
    expected = { keys = [ "flakeModules" ]; modNames = [ "mymod" ]; };
  };

  # Users build custom module exports from scanDir + entryPath
  testUserCanBuildCustomModuleExport = {
    expr =
      let
        nixosMods = builtins.mapAttrs (_: e: entryPath e) (scanDir (fixtures + "/full/modules/nixos"));
      in builtins.sort builtins.lessThan (builtins.attrNames nixosMods);
    expected = [ "injected" "server" ];
  };
}
