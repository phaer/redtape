{
  description = "red-tape — convention-based project builder on adios-flake";

  inputs = {
    adios-flake.url = "github:Mic92/adios-flake";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { adios-flake, nixpkgs, ... }:
    let
      imported = import ./nix { inherit adios-flake; };
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      eachSystem = f: builtins.foldl' (acc: system: acc // {
        ${system} = f (import nixpkgs { inherit system; });
      }) {} systems;
    in
    {
      lib = imported;

      mkFlake = args:
        imported.mkFlake (args // {
          systems = args.systems or systems;
        });

      devShells = eachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.nix-unit
            pkgs.nixfmt-tree
          ];
        };
      });
    };
}
