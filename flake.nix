{
  description = "red-tape — convention-based project builder on adios";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    adios.url = "github:adisbladis/adios/6754e85bce51ea198fa405394fb5b57d67555e7d";
    systems.url = "github:nix-systems/default";
  };

  outputs = inputs@{ self, nixpkgs, adios, systems, ... }:
    let
      adiosLib = adios.adios;
      redTape = import ./lib/mk-red-tape.nix { adios = adiosLib; };
      defaultSystems = import systems;

      # red-tape's own outputs (packages, devshells, etc.)
      selfOutputs = redTape.mkFlake {
        inherit inputs;
        src = ./.;
        systems = defaultSystems;
      };
    in
    selfOutputs // {
      # Export the library for consumers
      lib = redTape // {
        # Make red-tape callable: inputs.red-tape { inherit inputs; }
        __functor = _: args:
          redTape.mkFlake (args // {
            systems = args.systems or defaultSystems;
          });
      };

      # Re-export adios for consumers that need it
      inherit (adios) adios;
    };
}
