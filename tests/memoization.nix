# Memoization tests
#
# Tests that adios override correctly:
# 1. Re-evaluates modules that depend on changed inputs (/nixpkgs)
# 2. Memoizes modules that DON'T depend on changed inputs
# 3. Produces correct results for all systems
#
# We can't directly observe memoization (no evalParams in current API),
# but we verify the override mechanism produces correct results — which
# is the observable guarantee adios provides.

let
  prelude = import ./prelude.nix;
  inherit (prelude) adios;

  loaded = adios {
    name = "memo-test";
    modules = {
      nixpkgs = {
        name = "nixpkgs";
        options.system = { type = adios.types.string; };
        options.pkgs = { type = adios.types.attrs; };
      };

      # System-dependent: depends on /nixpkgs
      packages = {
        name = "packages";
        inputs.nixpkgs = { path = "/nixpkgs"; };
        options.discovered = { type = adios.types.attrs; default = {}; };
        impl = { inputs, options, ... }: {
          system = inputs.nixpkgs.system;
          names = builtins.attrNames options.discovered;
        };
      };

      # System-independent: no /nixpkgs dependency
      pure = {
        name = "pure";
        options.data = { type = adios.types.attrs; default = { answer = 42; }; };
        impl = { options, ... }: {
          value = options.data;
          computed = options.data.answer * 2;
        };
      };
    };
  };

  discovered = { hello = {}; };

  e1 = loaded {
    options = {
      "/nixpkgs" = { system = "x86_64-linux"; pkgs = {}; };
      "/packages" = { inherit discovered; };
      "/pure" = {};
    };
  };

  e2 = e1.override {
    options = {
      "/nixpkgs" = { system = "aarch64-linux"; pkgs = {}; };
      "/packages" = { inherit discovered; };
    };
  };

  e3 = e2.override {
    options = {
      "/nixpkgs" = { system = "x86_64-darwin"; pkgs = {}; };
      "/packages" = { inherit discovered; };
    };
  };

in
{
  # System-dependent module correctly changes per system
  testSystemDependentChanges = {
    expr = {
      sys1 = (e1.modules.packages {}).system;
      sys2 = (e2.modules.packages {}).system;
      sys3 = (e3.modules.packages {}).system;
    };
    expected = {
      sys1 = "x86_64-linux";
      sys2 = "aarch64-linux";
      sys3 = "x86_64-darwin";
    };
  };

  # Pure module produces identical results across all systems
  testPureIdenticalAcrossSystems = {
    expr = {
      e1 = (e1.modules.pure {}).computed;
      e2 = (e2.modules.pure {}).computed;
      e3 = (e3.modules.pure {}).computed;
    };
    expected = {
      e1 = 84;
      e2 = 84;
      e3 = 84;
    };
  };

  # Discovered data preserved across overrides
  testDiscoveredPreservedAcrossOverrides = {
    expr = {
      sys1 = (e1.modules.packages {}).names;
      sys2 = (e2.modules.packages {}).names;
    };
    expected = {
      sys1 = [ "hello" ];
      sys2 = [ "hello" ];
    };
  };

  # Override chain: e1 results unchanged after e2/e3 creation
  testFirstEvalStableAfterOverrides = {
    expr = (e1.modules.packages {}).system;
    expected = "x86_64-linux";
  };

  # Module functor calls produce correct results
  testFunctorCallsCorrect = {
    expr = {
      r1 = (e1.modules.packages {}).system;
      r2 = (e2.modules.packages {}).system;
      pure = (e1.modules.pure {}).computed;
    };
    expected = {
      r1 = "x86_64-linux";
      r2 = "aarch64-linux";
      pure = 84;
    };
  };
}
