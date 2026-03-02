# Tests for module export
let
  prelude = import ./prelude.nix;
  inherit (prelude) _internal fixtures;
  inherit (_internal) discover;
  inherit (_internal.builders) buildModules;

  full = buildModules {
    discovered = (discover.discoverAll (fixtures + "/full")).modules;
    flakeInputs = {};
    self = null;
  };

  empty = buildModules { discovered = {}; flakeInputs = {}; self = null; };
in
{
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

  testPlainModuleIsPath = {
    expr = builtins.isPath full.nixosModules.server;
    expected = true;
  };

  testInjectedModuleIsFunction = {
    expr = builtins.isFunction full.nixosModules.injected;
    expected = true;
  };

  testEmptyModules = {
    expr = empty;
    expected = {};
  };
}
