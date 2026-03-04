# Tests for module export
let
  prelude = import ./prelude.nix;
  inherit (prelude) discover builders fixtures;
  inherit (builders) buildModules;

  full = buildModules {
    discovered = (discover.discoverAll (fixtures + "/full")).modules;
  };

  empty = buildModules { discovered = { }; };
in
{
  testOutputKeys = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames full);
    expected = [ "modules" "nixosModules" ];
  };

  testModulesHierarchy = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames full.modules);
    expected = [ "darwin" "home" "nixos" ];
  };

  testModulesNixosMatchesNixosModules = {
    expr = builtins.attrNames full.modules.nixos;
    expected = builtins.attrNames full.nixosModules;
  };

  testNixosModuleNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames full.nixosModules);
    expected = [
      "injected"
      "server"
    ];
  };

  testPlainModuleIsPath = {
    expr = builtins.isPath full.nixosModules.server;
    expected = true;
  };

  testInjectedModuleHasFileLocation = {
    expr =
      let
        mod = full.nixosModules.injected;
      in
      {
        isAttrset = builtins.isAttrs mod;
        hasFile = mod ? _file;
        hasImports = mod ? imports;
        fileEndsWithNix = builtins.match ".*injected\\.nix" mod._file != null;
      };
    expected = {
      isAttrset = true;
      hasFile = true;
      hasImports = true;
      fileEndsWithNix = true;
    };
  };

  testInjectedModuleReceivesPublisherArgs = {
    expr =
      let
        fakeSelf = {
          outPath = "/my/flake";
        };
        result = buildModules {
          discovered = (discover.discoverAll (fixtures + "/full")).modules;
          inputs = {
            nixpkgs = "fake-nixpkgs";
            self = fakeSelf;
          };
          self = fakeSelf;
        };
        wrappedFn = builtins.head result.nixosModules.injected.imports;
        modBody = wrappedFn { };
      in
      {
        hasFlake = modBody._publisherFlake == fakeSelf;
        hasInputs = modBody._publisherInputs ? nixpkgs;
        hasSelf = modBody._publisherInputs ? self;
      };
    expected = {
      hasFlake = true;
      hasInputs = true;
      hasSelf = true;
    };
  };

  testEmptyModules = {
    expr = empty;
    expected = { };
  };
}
