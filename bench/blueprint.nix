# Evaluate blueprint with the full test fixture
let
  blueprintFlake = builtins.getFlake "github:numtide/blueprint";
  nixpkgsFlake = builtins.getFlake "github:NixOS/nixpkgs/nixos-unstable";

  blueprint = import (blueprintFlake.outPath + "/lib") {
    inputs = {
      nixpkgs = nixpkgsFlake;
      inherit (blueprintFlake.inputs) systems;
    };
  };

  result = blueprint {
    inputs = {
      nixpkgs = nixpkgsFlake;
      self = result;
      inherit (blueprintFlake.inputs) systems;
    };
    prefix = ../tests/fixtures/full;
    systems = [ "x86_64-linux" ];
  };

  # blueprint passes different args to lib/ than red-tape, so skip checks
  # (which would force lib evaluation via __functor). Evaluate the same
  # output categories that don't depend on lib.
  names = {
    packages = builtins.attrNames (result.packages.x86_64-linux or { });
    devShells = builtins.attrNames (result.devShells.x86_64-linux or { });
    formatter = (result.formatter.x86_64-linux or { }).name or null;
    nixosConfigurations = builtins.attrNames (result.nixosConfigurations or { });
    nixosModules = builtins.attrNames (result.nixosModules or { });
    templates = builtins.attrNames (result.templates or { });
  };
in
builtins.deepSeq names names
