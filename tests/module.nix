# Tests for the adios module tree
{ adios-flake }:
let
  prelude = import ./prelude.nix;
  inherit (prelude) mockPkgs sys fixtures;

  adiosLib = adios-flake.inputs.adios.adios;
  redTape = import ../lib { inherit adios-flake; };

  evalFixture =
    {
      src,
      prefix ? null,
      modulesOpts ? { },
    }:
    let
      rootDef = {
        modules = {
          "red-tape" = builtins.removeAttrs redTape.modules.redTape.default [ "name" ];
          nixpkgs = {
            options = {
              system = {
                type = adiosLib.types.string;
              };
              pkgs = {
                type = adiosLib.types.attrs;
              };
            };
          };
        };
      };
      tree = adiosLib rootDef {
        options = {
          "/red-tape/scan" = {
            inherit src;
          }
          // (if prefix != null then { inherit prefix; } else { });
          "/red-tape/modules" = modulesOpts;
          "/nixpkgs" = {
            system = sys;
            pkgs = mockPkgs;
          };
          "/red-tape" = { };
          "/red-tape/scope" = { };
          "/red-tape/packages" = { };
          "/red-tape/devshells" = { };
          "/red-tape/checks" = { };
          "/red-tape/formatter" = { };
          "/red-tape/hosts" = { };
          "/red-tape/templates" = { };
          "/red-tape/lib" = { };
        };
      };
    in
    tree.modules.${"red-tape"} { };

  fullResult = evalFixture { src = fixtures + "/full"; };
  prefixResult = evalFixture {
    src = fixtures + "/prefixed";
    prefix = "nix";
  };
  minimalResult = evalFixture { src = fixtures + "/minimal"; };
in
{
  testModulePackageNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames fullResult.packages);
    expected = [
      "formatter"
      "goodbye"
      "hello"
    ];
  };
  testModuleDevShellNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames fullResult.devShells);
    expected = [
      "backend"
      "default"
    ];
  };
  testModuleFormatterPresent = {
    expr = fullResult.formatter != null;
    expected = true;
  };
  testMinimalChecksHasPackage = {
    expr = minimalResult.checks ? "pkgs-default";
    expected = true;
  };
  testPrefixModulePackageNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames prefixResult.packages);
    expected = [
      "default"
      "formatter"
      "widget"
    ];
  };
  testMinimalFormatterFallback = {
    expr = minimalResult.formatter.name;
    expected = "nixfmt-tree";
  };
  testNixosModuleNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames fullResult.nixosModules);
    expected = [
      "injected"
      "server"
    ];
  };
  testTemplateNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames fullResult.templates);
    expected = [
      "default"
      "minimal"
    ];
  };
  testLibPresent = {
    expr = fullResult ? lib;
    expected = true;
  };
}
