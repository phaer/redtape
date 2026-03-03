# Tests for the flakeOutputs API
let
  prelude = import ./prelude.nix;
  inherit (prelude) fixtures;

  adios-flake = builtins.getFlake "github:Mic92/adios-flake";
  redTape = import ../nix { inherit adios-flake; };

  # Test: flakeOutputs from full fixture
  fullResult = redTape.flakeOutputs { src = fixtures + "/full"; };

  # Test: flakeOutputs from simple fixture (no hosts, modules, etc.)
  simpleResult = redTape.flakeOutputs { src = fixtures + "/simple"; };

  # Test: flakeOutputs with extra type aliases
  customModResult = redTape.flakeOutputs {
    src = fixtures + "/custom-modules";
    moduleTypeAliases = { flake = "flakeModules"; };
  };
in
{
  # --- Full fixture ---

  testOverlayNames = {
    expr = builtins.attrNames fullResult.overlays;
    expected = [ "default" ];
  };

  testOverlayIsFunction = {
    expr = builtins.isFunction fullResult.overlays.default;
    expected = true;
  };

  testNixosModuleNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames fullResult.nixosModules);
    expected = [ "injected" "server" ];
  };

  testHomeModuleNames = {
    expr = builtins.attrNames fullResult.homeModules;
    expected = [ "shared" ];
  };

  testDarwinModuleNames = {
    expr = builtins.attrNames fullResult.darwinModules;
    expected = [ "defaults" ];
  };

  testTemplateNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames fullResult.templates);
    expected = [ "default" "minimal" ];
  };

  testLibPresent = {
    expr = fullResult ? lib;
    expected = true;
  };

  testNoInternalLeakage = {
    expr = fullResult ? _redTape;
    expected = false;
  };

  # --- Simple fixture (no system-agnostic outputs except overlays) ---

  testSimpleOverlays = {
    expr = builtins.attrNames simpleResult.overlays;
    expected = [ "my-overlay" ];
  };

  testSimpleNoModules = {
    expr = simpleResult ? nixosModules;
    expected = false;
  };

  testSimpleNoHosts = {
    expr = simpleResult ? nixosConfigurations;
    expected = false;
  };

  # --- Custom module type aliases ---

  testCustomTypeAlias = {
    expr = builtins.attrNames (customModResult.flakeModules or {});
    expected = [ "mymod" ];
  };
}
