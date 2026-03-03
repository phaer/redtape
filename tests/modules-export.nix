# Tests for module export
let
  prelude = import ./prelude.nix;
  inherit (prelude) discover builders fixtures;
  inherit (builders) buildModules;

  full = buildModules {
    discovered = (discover.discoverAll (fixtures + "/full")).modules;
    allInputs = {};
    self = null;
  };

  empty = buildModules { discovered = {}; allInputs = {}; self = null; };
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

  # Injected modules are wrapped with { _file; imports } for error locations
  testInjectedModuleHasFileLocation = {
    expr =
      let mod = full.nixosModules.injected;
      in {
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

  # Publisher args are injected at export time
  testInjectedModuleReceivesPublisherArgs = {
    expr =
      let
        fakeSelf = { outPath = "/my/flake"; };
        result = buildModules {
          discovered = (discover.discoverAll (fixtures + "/full")).modules;
          allInputs = { nixpkgs = "fake-nixpkgs"; self = fakeSelf; };
          self = fakeSelf;
        };
        # The wrapped module function is in imports
        wrappedFn = builtins.head result.nixosModules.injected.imports;
        modBody = wrappedFn {};
      in {
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
    expected = {};
  };
}
