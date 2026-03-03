{
  description = "red-tape — convention-based project builder on adios-flake";

  inputs = {
    adios-flake.url = "github:phaer/adios-flake/flake-outputs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { adios-flake, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      eachSystem =
        f:
        builtins.foldl' (
          acc: system:
          acc
          // {
            ${system} = f (import nixpkgs { inherit system; });
          }
        ) { } systems;
    in
    {
      checks = eachSystem (pkgs: {
        unit-tests =
          pkgs.runCommand "red-tape-tests"
            {
              nativeBuildInputs = [ pkgs.nix-unit ];
            }
            ''
              nix-unit ${./tests/default.nix}
              touch $out
            '';
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
