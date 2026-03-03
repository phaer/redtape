# Test prelude — shared setup for all test files
let
  adios-flake = builtins.getFlake "github:Mic92/adios-flake";
  redTape = import ../nix { inherit adios-flake; };

  lib = import <nixpkgs/lib>;

  mockPkgs = {
    system = "x86_64-linux";
    inherit lib;
    mkShell = args: { type = "devshell"; } // args;
    hello = { type = "derivation"; name = "hello"; meta = {}; };
    writeShellScriptBin = name: text: {
      type = "derivation"; inherit name; meta = {};
    };
    runCommand = name: env: cmd: {
      type = "derivation"; inherit name; meta = {};
    };
    nodejs = { type = "derivation"; name = "nodejs"; meta = {}; };
    nixfmt-tree = { type = "derivation"; name = "nixfmt-tree"; meta = {}; };
  };

  sys = "x86_64-linux";
  fixtures = ../tests/fixtures;
in
{
  inherit mockPkgs sys fixtures;
  _internal = redTape._internal;
}
