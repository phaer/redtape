# Evaluate redtape with the full test fixture
let
  redtapeFlake = builtins.getFlake (toString ./..);
  nixpkgsFlake = builtins.getFlake "github:NixOS/nixpkgs/nixos-unstable";

  inputs = {
    nixpkgs = nixpkgsFlake;
    self = result;
  };

  result = redtapeFlake.mkFlake {
    inherit inputs;
    src = ../tests/fixtures/full;
    self = result;
    systems = [ "x86_64-linux" ];
  };

  # Force evaluation of key outputs without serializing derivations.
  # Skipping checks to match blueprint (whose checks depend on lib/__functor
  # which is incompatible with this fixture).
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
