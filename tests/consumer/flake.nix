{
  description = "red-tape consumer integration test";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    red-tape.url = "path:../..";
    red-tape.inputs = {};
  };

  outputs = inputs: inputs.red-tape.mkFlake {
    inherit inputs;
    src = ./.;
    systems = [ "x86_64-linux" ];
  };
}
