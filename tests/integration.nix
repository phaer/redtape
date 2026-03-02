# Integration tests — builders with mock pkgs
let
  prelude = import ./prelude.nix;
  inherit (prelude) mockPkgs sys fixtures _internal;
  inherit (_internal) discover;
  inherit (_internal.builders) buildPackages buildDevshells buildChecks buildFormatter buildOverlays;

  evalFixture = src:
    let
      found = discover.discoverAll src;
      scope = { pkgs = mockPkgs; system = sys; lib = mockPkgs.lib; };

      pkg = if found.packages != null
        then buildPackages { discovered = found.packages; inherit scope; system = sys; }
        else { packages = {}; autoChecks = {}; };

      dev = if found.devshells != null
        then buildDevshells { discovered = found.devshells; inherit scope; }
        else { devShells = {}; autoChecks = {}; };

      chk = if found.checks != null
        then buildChecks { discovered = found.checks; inherit scope; system = sys; }
        else { checks = {}; };

      fmt = buildFormatter { formatterPath = found.formatter; inherit scope; pkgs = mockPkgs; };

      ovl = if found.overlays != null
        then buildOverlays { discovered = found.overlays; inherit scope; }
        else {};
    in
    {
      inherit (pkg) packages;
      inherit (dev) devShells;
      formatter = fmt;
      checks = chk.checks;
      overlays = ovl.overlays or {};
    };
in
{
  testSimplePackageNames = {
    expr = builtins.sort builtins.lessThan
      (builtins.attrNames (evalFixture (fixtures + "/simple")).packages);
    expected = [ "goodbye" "hello" ];
  };

  testPackageType = {
    expr = (evalFixture (fixtures + "/simple")).packages.hello.type;
    expected = "derivation";
  };

  testDevshellNames = {
    expr = builtins.sort builtins.lessThan
      (builtins.attrNames (evalFixture (fixtures + "/simple")).devShells);
    expected = [ "backend" "default" ];
  };

  testSimpleFormatter = {
    expr = (evalFixture (fixtures + "/simple")).formatter != null;
    expected = true;
  };

  testFormatterFallback = {
    expr = (evalFixture (fixtures + "/minimal")).formatter.name;
    expected = "nixfmt-tree";
  };

  testCheckNames = {
    expr = builtins.sort builtins.lessThan
      (builtins.attrNames (evalFixture (fixtures + "/simple")).checks);
    expected = [ "mycheck" ];
  };

  # Overlay names from simple fixture
  testSimpleOverlayNames = {
    expr = builtins.attrNames (evalFixture (fixtures + "/simple")).overlays;
    expected = [ "my-overlay" ];
  };

  # Overlay is a function (final: prev: { ... })
  testOverlayIsFunction = {
    expr = builtins.isFunction (evalFixture (fixtures + "/simple")).overlays.my-overlay;
    expected = true;
  };

  # No overlays in minimal
  testMinimalNoOverlays = {
    expr = (evalFixture (fixtures + "/minimal")).overlays;
    expected = {};
  };
}
