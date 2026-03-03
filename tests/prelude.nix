# Test prelude — shared setup for all test files
let
  discover = import ../lib/discover.nix;

  lib = import <nixpkgs/lib>;

  mockPkgs = {
    system = "x86_64-linux";
    inherit lib;
    mkShell = args: { type = "devshell"; } // args;
    hello = {
      type = "derivation";
      name = "hello";
      meta = { };
    };
    custom-tool = {
      type = "derivation";
      name = "custom-tool";
      meta = { };
    };
    writeShellScriptBin = name: text: {
      type = "derivation";
      inherit name;
      meta = { };
    };
    runCommand = name: env: cmd: {
      type = "derivation";
      inherit name;
      meta = { };
    };
    nodejs = {
      type = "derivation";
      name = "nodejs";
      meta = { };
    };
    nixfmt-tree = {
      type = "derivation";
      name = "nixfmt-tree";
      meta = { };
    };
  };

  sys = "x86_64-linux";
  fixtures = ../tests/fixtures;

  helpers = import ../lib/utils.nix;
in
{
  inherit
    mockPkgs
    sys
    fixtures
    discover
    helpers
    ;
}
