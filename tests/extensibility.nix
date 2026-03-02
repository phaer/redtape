# Tests for extensibility — custom host types and module types via adios-flake modules
let
  prelude = import ./prelude.nix;
  inherit (prelude) _internal fixtures;
  inherit (_internal) discover;
  inherit (_internal.builders) buildModules;

  scanHosts = discover.scanHosts;
  scanDir = discover.scanDir;
in
{
  # --- Custom host types via scanHosts ---

  # Users can scan for custom sentinel files
  testScanCustomHostType = {
    expr =
      let
        found = scanHosts (fixtures + "/custom-hosts/hosts") [
          { type = "nix-on-droid"; file = "droid-configuration.nix"; }
        ];
      in {
        names = builtins.attrNames found;
        type = found.myphone.type;
      };
    expected = {
      names = [ "myphone" ];
      type = "nix-on-droid";
    };
  };

  # Core host types don't match custom sentinel files
  testCoreHostTypesIgnoreCustom = {
    expr =
      let found = discover.discoverAll (fixtures + "/custom-hosts");
      in found.hosts;
    expected = null;
  };

  # scanHosts with multiple types, first match wins
  testScanHostsFirstMatchWins = {
    expr =
      let
        found = scanHosts (fixtures + "/full/hosts") [
          { type = "custom"; file = "default.nix"; }
          { type = "nixos"; file = "configuration.nix"; }
        ];
      in {
        # myhost has both default.nix? No — only configuration.nix
        # custom has default.nix → custom wins
        customType = found.custom.type;
        myhostType = found.myhost.type;
      };
    expected = {
      customType = "custom";
      myhostType = "nixos";
    };
  };

  # --- Custom module export types ---

  # Users can scan arbitrary module type directories
  testScanCustomModuleType = {
    expr =
      let
        # scanModuleTypes finds all subdirs under modules/
        mods = discover.scanModuleTypes (fixtures + "/full/modules");
      in builtins.sort builtins.lessThan (builtins.attrNames mods);
    # modules/darwin, modules/home, modules/nixos all present
    expected = [ "darwin" "home" "nixos" ];
  };

  # Unknown type aliases are silently skipped by buildModules
  testUnknownTypeAliasSkipped = {
    expr =
      let
        result = buildModules {
          discovered = {
            # "flake" is not in the hardcoded typeAliases
            flake = discover.scanDir (fixtures + "/full/modules/nixos");
          };
          flakeInputs = {};
          self = null;
        };
      in result;
    expected = {};
  };

  # extraTypeAliases lets users register new module types
  testExtraTypeAliases = {
    expr =
      let
        result = buildModules {
          discovered = (discover.discoverAll (fixtures + "/custom-modules")).modules;
          flakeInputs = {};
          self = null;
          extraTypeAliases = { flake = "flakeModules"; };
        };
      in {
        keys = builtins.attrNames result;
        modNames = builtins.attrNames (result.flakeModules or {});
      };
    expected = {
      keys = [ "flakeModules" ];
      modNames = [ "mymod" ];
    };
  };

  # Users can build their own module export from raw scanDir + scanModuleTypes
  testUserCanBuildCustomModuleExport = {
    expr =
      let
        mods = discover.scanModuleTypes (fixtures + "/full/modules");
        # User manually maps "nixos" entries to their own output key
        nixosMods = builtins.mapAttrs (_: entry:
          let path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
          in path
        ) (mods.nixos or {});
      in builtins.sort builtins.lessThan (builtins.attrNames nixosMods);
    expected = [ "injected" "server" ];
  };
}
