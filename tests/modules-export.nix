# Tests for module export
let
  buildModules = import ../lib/build-modules.nix {
    flakeInputs = {};
    self = null;
  };
  discover = import ../modules/discover.nix;
  fixtures = ../tests/fixtures;

  full = buildModules (discover (fixtures + "/full")).modules;
  empty = buildModules (discover (fixtures + "/empty")).modules;
in
{
  # Well-known aliases are the only output keys
  testOutputKeys = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames full);
    expected = [ "darwinModules" "homeModules" "nixosModules" ];
  };

  testNixosModuleNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames full.nixosModules);
    expected = [ "injected" "server" ];
  };

  testHomeModuleNames = {
    expr = builtins.attrNames full.homeModules;
    expected = [ "shared" ];
  };

  testDarwinModuleNames = {
    expr = builtins.attrNames full.darwinModules;
    expected = [ "defaults" ];
  };

  # Plain modules (no publisher args) are re-exported as paths
  testPlainModuleIsPath = {
    expr = builtins.isPath full.nixosModules.server;
    expected = true;
  };

  # Publisher-args modules are called and return a function (the inner module)
  testInjectedModuleIsFunction = {
    expr = builtins.isFunction full.nixosModules.injected;
    expected = true;
  };

  # Empty project produces no output
  testEmptyModules = {
    expr = empty;
    expected = {};
  };
}
