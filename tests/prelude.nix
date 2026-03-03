# Test prelude — shared setup for all test files
let
  adios-flake = builtins.getFlake "github:phaer/adios-flake/flake-outputs";
  adiosLib = adios-flake.inputs.adios.adios;

  discover = import ../nix/discover.nix;
  helpers = import ../nix/helpers.nix;
  builders = import ../nix/builders.nix;
  redTape = import ../nix { inherit adios-flake; };

  lib = import <nixpkgs/lib>;

  mockPkgs = {
    system = "x86_64-linux";
    inherit lib;
    mkShell = args: { type = "devshell"; } // args;
    hello = { type = "derivation"; name = "hello"; meta = {}; };
    writeShellScriptBin = name: text: { type = "derivation"; inherit name; meta = {}; };
    runCommand = name: env: cmd: { type = "derivation"; inherit name; meta = {}; };
    nodejs = { type = "derivation"; name = "nodejs"; meta = {}; };
    nixfmt-tree = { type = "derivation"; name = "nixfmt-tree"; meta = {}; };
  };

  sys = "x86_64-linux";
  fixtures = ../tests/fixtures;
in
{
  inherit mockPkgs sys fixtures adiosLib discover helpers builders redTape;
}
