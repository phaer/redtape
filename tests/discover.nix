# Tests for the discover module
let
  prelude = import ./prelude.nix;
  inherit (prelude) _internal fixtures;
  inherit (_internal) discover;
  discoverAll = discover.discoverAll;
in
{
  # --- Packages ---

  testDiscoverPackages = {
    expr = builtins.sort builtins.lessThan
      (builtins.attrNames (discoverAll (fixtures + "/simple")).packages);
    expected = [ "goodbye" "hello" ];
  };

  testDiscoverPackageNix = {
    expr = builtins.attrNames (discoverAll (fixtures + "/minimal")).packages;
    expected = [ "default" ];
  };

  # --- DevShells ---

  testDiscoverDevshells = {
    expr = builtins.sort builtins.lessThan
      (builtins.attrNames (discoverAll (fixtures + "/simple")).devshells);
    expected = [ "backend" "default" ];
  };

  # --- Formatter ---

  testDiscoverFormatter = {
    expr = (discoverAll (fixtures + "/simple")).formatter != null;
    expected = true;
  };

  testNoFormatter = {
    expr = (discoverAll (fixtures + "/minimal")).formatter;
    expected = null;
  };

  # --- Checks ---

  testDiscoverChecks = {
    expr = builtins.attrNames (discoverAll (fixtures + "/simple")).checks;
    expected = [ "mycheck" ];
  };

  # --- Empty ---

  testDiscoverEmpty = {
    expr =
      let result = discoverAll (fixtures + "/empty");
      in {
        hasPackages  = result.packages != null;
        hasDevshells = result.devshells != null;
        hasChecks    = result.checks != null;
        hasHosts     = result.hosts != null;
        hasOverlays  = result.overlays != null;
        hasModules   = result.modules != null;
        formatter    = result.formatter;
        templates    = result.templates;
      };
    expected = {
      hasPackages  = false;
      hasDevshells = false;
      hasChecks    = false;
      hasHosts     = false;
      hasOverlays  = false;
      hasModules   = false;
      formatter    = null;
      templates    = {};
    };
  };

  # --- Overlays ---

  testDiscoverOverlays = {
    expr = builtins.attrNames (discoverAll (fixtures + "/simple")).overlays;
    expected = [ "my-overlay" ];
  };

  testDiscoverOverlayNix = {
    expr = builtins.attrNames (discoverAll (fixtures + "/full")).overlays;
    expected = [ "default" ];
  };

  testNoOverlays = {
    expr = (discoverAll (fixtures + "/minimal")).overlays;
    expected = null;
  };

  # --- Hosts ---

  testDiscoverHosts = {
    expr = builtins.sort builtins.lessThan
      (builtins.attrNames (discoverAll (fixtures + "/full")).hosts);
    expected = [ "custom" "myhost" "mymac" ];
  };

  testHostConfigTypes = {
    expr =
      let hosts = (discoverAll (fixtures + "/full")).hosts;
      in {
        myhost = hosts.myhost.type;
        mymac = hosts.mymac.type;
        custom = hosts.custom.type;
      };
    expected = {
      myhost = "nixos";
      mymac = "custom";  # default.nix escape hatch
      custom = "custom";
    };
  };

  # --- Modules ---

  testDiscoverModuleTypes = {
    expr =
      let mods = (discoverAll (fixtures + "/full")).modules;
      in builtins.sort builtins.lessThan (builtins.attrNames mods);
    expected = [ "darwin" "home" "nixos" ];
  };

  testDiscoverNixosModules = {
    expr = builtins.sort builtins.lessThan
      (builtins.attrNames (discoverAll (fixtures + "/full")).modules.nixos);
    expected = [ "injected" "server" ];
  };

  testDiscoverHomeModules = {
    expr = builtins.attrNames (discoverAll (fixtures + "/full")).modules.home;
    expected = [ "shared" ];
  };

  # --- Templates ---

  testDiscoverTemplates = {
    expr = builtins.sort builtins.lessThan
      (builtins.attrNames (discoverAll (fixtures + "/full")).templates);
    expected = [ "default" "minimal" ];
  };

  # --- Lib ---

  testDiscoverLib = {
    expr = (discoverAll (fixtures + "/full")).lib != null;
    expected = true;
  };

  testNoLib = {
    expr = (discoverAll (fixtures + "/simple")).lib;
    expected = null;
  };
}
