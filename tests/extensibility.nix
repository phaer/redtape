let
  prelude = import ./prelude.nix;
  inherit (prelude)
    discover
    helpers
    builders
    fixtures
    ;
  inherit (helpers) entryPath;
  inherit (builders) buildModules;
  inherit (discover) scanDir scanHosts;
in
{
  testScanCustomHostType = {
    expr =
      let
        found = scanHosts (fixtures + "/custom-hosts/hosts") [
          {
            type = "nix-on-droid";
            file = "droid-configuration.nix";
          }
        ];
      in
      {
        names = builtins.attrNames found;
        type = found.myphone.type;
      };
    expected = {
      names = [ "myphone" ];
      type = "nix-on-droid";
    };
  };
  testCoreHostTypesIgnoreCustom = {
    expr = (discover.discoverAll (fixtures + "/custom-hosts")).hosts;
    expected = { };
  };
  testScanHostsFirstMatchWins = {
    expr =
      let
        found = scanHosts (fixtures + "/full/hosts") [
          {
            type = "custom";
            file = "default.nix";
          }
          {
            type = "nixos";
            file = "configuration.nix";
          }
        ];
      in
      {
        customType = found.custom.type;
        myhostType = found.myhost.type;
      };
    expected = {
      customType = "custom";
      myhostType = "nixos";
    };
  };
  testScanModuleSubdirs = {
    expr =
      let
        modulesPath = fixtures + "/full/modules";
        entries = builtins.readDir modulesPath;
        types = builtins.filter (n: entries.${n} == "directory") (builtins.attrNames entries);
      in
      builtins.sort builtins.lessThan types;
    expected = [
      "darwin"
      "home"
      "nixos"
    ];
  };
  testUnknownModuleTypeSkipped = {
    expr =
      let
        result = buildModules {
          discovered = {
            flake = scanDir (fixtures + "/full/modules/nixos");
          };
        };
      in
      {
        hasAlias = result ? flakeModules;
        hasHierarchy = result ? modules;
        hierarchyKeys = builtins.attrNames result.modules;
      };
    expected = {
      hasAlias = false;
      hasHierarchy = true;
      hierarchyKeys = [ "flake" ];
    };
  };
  testExtraModuleTypes = {
    expr =
      let
        result = buildModules {
          discovered = (discover.discoverAll (fixtures + "/custom-modules")).modules;
          extraModuleTypes = {
            flake = "flakeModules";
          };
        };
      in
      {
        keys = builtins.sort builtins.lessThan (builtins.attrNames result);
        modNames = builtins.attrNames (result.flakeModules or { });
      };
    expected = {
      keys = [ "flakeModules" "modules" ];
      modNames = [ "mymod" ];
    };
  };
}
