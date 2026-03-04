# Tests for the discover module
let
  discover = import ../lib/discover.nix;
  inherit (discover) discoverAll;
  fixtures = ../tests/fixtures;

  sort = builtins.sort builtins.lessThan;
  names = s: builtins.attrNames s;
  d = path: discoverAll (fixtures + "/${path}");
in
{
  # --- Full fixture ---

  testFullPackages.expr = sort (names (d "full").packages);
  testFullPackages.expected = [
    "goodbye"
    "hello"
  ];

  testFullDevshells.expr = sort (names (d "full").devshells);
  testFullDevshells.expected = [
    "backend"
    "default"
  ];

  testFullChecks.expr = names (d "full").checks;
  testFullChecks.expected = [ "mycheck" ];

  testFullFormatter.expr = (d "full").formatter != null;
  testFullFormatter.expected = true;

  testFullHosts.expr = sort (names (d "full").hosts);
  testFullHosts.expected = [
    "custom"
    "db"
    "monitoring"
    "myhost"
    "mymac"
  ];

  testFullHostTypes = {
    expr =
      let
        h = (d "full").hosts;
      in
      {
        myhost = h.myhost.type;
        mymac = h.mymac.type;
        custom = h.custom.type;
      };
    expected = {
      myhost = "nixos";
      mymac = "custom";
      custom = "custom";
    };
  };

  testFullModuleTypes.expr = sort (names (d "full").modules);
  testFullModuleTypes.expected = [
    "darwin"
    "home"
    "nixos"
  ];

  testFullNixosModules.expr = sort (names (d "full").modules.nixos);
  testFullNixosModules.expected = [
    "injected"
    "server"
  ];

  testFullHomeModules.expr = names (d "full").modules.home;
  testFullHomeModules.expected = [ "shared" ];

  testFullTemplates.expr = sort (names (d "full").templates);
  testFullTemplates.expected = [
    "default"
    "minimal"
  ];

  testFullLib.expr = (d "full").lib != null;
  testFullLib.expected = true;

  # --- Minimal fixture ---

  testMinimalPackage.expr = names (d "minimal").packages;
  testMinimalPackage.expected = [ "default" ];

  testMinimalNoFormatter.expr = (d "minimal").formatter;
  testMinimalNoFormatter.expected = null;

  # --- Empty fixture ---

  testEmpty = {
    expr =
      let
        r = d "empty";
      in
      {
        inherit (r)
          packages
          devshells
          checks
          hosts
          modules
          formatter
          templates
          ;
      };
    expected = {
      packages = { };
      devshells = { };
      checks = { };
      hosts = { };
      modules = { };
      formatter = null;
      templates = { };
    };
  };

  # --- Prefixed fixture ---

  testPrefixedPackages.expr = sort (names (d "prefixed/nix").packages);
  testPrefixedPackages.expected = [
    "default"
    "widget"
  ];
}
