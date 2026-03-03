{
  description = "red-tape — convention-based project builder on adios-flake";

  inputs = {
    adios-flake.url = "github:phaer/adios-flake/flake-outputs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { adios-flake, nixpkgs, ... }:
    let
      redTape = import ./nix { inherit adios-flake; };
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      eachSystem = f: builtins.foldl' (acc: system: acc // {
        ${system} = f (import nixpkgs { inherit system; });
      }) {} systems;
    in
    {
      inherit (redTape) modules;

      mkFlake = args:
        redTape.mkFlake (args // {
          systems = args.systems or systems;
        });

      devShells = eachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.nix-unit pkgs.nixfmt-tree ];
        };
      });
    };
}
