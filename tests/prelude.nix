# Test prelude — shared setup for all test files
let
  flake = builtins.getFlake "git+file://${toString ./..}";
  redTape = flake.lib;

  realPkgs = import <nixpkgs> { system = "x86_64-linux"; };

  mockPkgs = {
    system = "x86_64-linux";
    lib = realPkgs.lib;
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
  inherit redTape realPkgs mockPkgs sys fixtures;
  _internal = redTape._internal;
}
