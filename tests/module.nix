# Tests for the adios module tree
let
  prelude = import ./prelude.nix;
  inherit (prelude) mockPkgs sys fixtures adiosLib;

  adios-flake = builtins.getFlake "github:phaer/adios-flake/flake-outputs";
  redTape = import ../nix { inherit adios-flake; };

  # Helper: evaluate a red-tape module tree against a fixture
  evalFixture = {
    src,
    prefix ? null,
    modulesOpts ? {},
  }:
    let
      rootDef = {
        modules = {
          "red-tape" = builtins.removeAttrs redTape.modules.default [ "name" ];
          nixpkgs = {
            options = {
              system = { type = adiosLib.types.string; };
              pkgs = { type = adiosLib.types.attrs; };
            };
          };
        };
      };

      tree = adiosLib rootDef {
        options = {
          "/red-tape/scan" = { inherit src; }
            // (if prefix != null then { inherit prefix; } else {});
          "/red-tape/modules" = modulesOpts;
          "/nixpkgs" = { system = sys; pkgs = mockPkgs; };
          "/red-tape" = {};
          "/red-tape/scope" = {};
          "/red-tape/packages" = {};
          "/red-tape/devshells" = {};
          "/red-tape/checks" = {};
          "/red-tape/formatter" = {};
          "/red-tape/hosts" = {};
          "/red-tape/overlays" = {};
          "/red-tape/templates" = {};
          "/red-tape/lib" = {};
        };
      };
    in
    tree.modules.${"red-tape"} {};

  # Test: simple fixture
  simpleResult = evalFixture { src = fixtures + "/simple"; };

  # Test: prefixed fixture
  prefixResult = evalFixture { src = fixtures + "/prefixed"; prefix = "nix"; };

  # Test: minimal fixture
  minimalResult = evalFixture { src = fixtures + "/minimal"; };

  # Test: full fixture
  fullResult = evalFixture { src = fixtures + "/full"; };

  # Test: custom module type aliases
  customModResult = evalFixture {
    src = fixtures + "/custom-modules";
    modulesOpts = { moduleTypeAliases = { flake = "flakeModules"; }; };
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

  # --- Full fixture: flake-scoped outputs ---

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

  # --- Custom module type aliases ---

  testCustomTypeAlias = {
    expr = builtins.attrNames (customModResult.flakeModules or {});
    expected = [ "mymod" ];
  };
}
