# Tests for the adios-flake module API
let
  prelude = import ./prelude.nix;
  inherit (prelude) mockPkgs sys fixtures;

  adios-flake = builtins.getFlake "github:Mic92/adios-flake";
  redTape = import ../nix { inherit adios-flake; };

  # Test: module produces per-system outputs from simple fixture
  simpleResult = redTape.module { src = fixtures + "/simple"; } {
    pkgs = mockPkgs;
    system = sys;
  };

  # Test: module with prefix
  prefixResult = redTape.module {
    src = fixtures + "/prefixed";
    prefix = "nix";
  } {
    pkgs = mockPkgs;
    system = sys;
  };

  # Test: module from minimal fixture
  minimalResult = redTape.module { src = fixtures + "/minimal"; } {
    pkgs = mockPkgs;
    system = sys;
  };
in
{
  # --- Simple fixture ---

  testModulePackageNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames simpleResult.packages);
    expected = [ "goodbye" "hello" ];
  };

  testModuleDevShellNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames simpleResult.devShells);
    expected = [ "backend" "default" ];
  };

  testModuleCheckNames = {
    expr = builtins.sort builtins.lessThan
      (builtins.attrNames (builtins.removeAttrs simpleResult.checks
        (builtins.filter (n: builtins.match "^(pkgs-|devshell-).*" n != null) (builtins.attrNames simpleResult.checks))));
    expected = [ "mycheck" ];
  };

  testModuleFormatterPresent = {
    expr = simpleResult.formatter != null;
    expected = true;
  };

  testModuleAutoChecksIncludePackages = {
    expr = simpleResult.checks ? "pkgs-hello";
    expected = true;
  };

  testModuleAutoChecksIncludeDevShells = {
    expr = simpleResult.checks ? "devshell-default";
    expected = true;
  };

  # --- Prefix ---

  testPrefixModulePackageNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames prefixResult.packages);
    expected = [ "default" "widget" ];
  };

  # --- Minimal ---

  testMinimalFormatterFallback = {
    expr = minimalResult.formatter.name;
    expected = "nixfmt-tree";
  };
}
