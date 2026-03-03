# Tests for lib export
let
  prelude = import ./prelude.nix;
  inherit (prelude) discover fixtures;

  importLib = libPath: args:
    if libPath == null then {}
    else let mod = import libPath;
    in if builtins.isFunction mod then mod args else mod;
in
{
  testLibPresent = {
    expr = (discover.discoverAll (fixtures + "/full")).lib != null;
    expected = true;
  };

  testLibImport = {
    expr =
      let
        libPath = (discover.discoverAll (fixtures + "/full")).lib;
        lib = importLib libPath { flake = null; inputs = {}; };
      in
      lib.greet "world";
    expected = "Hello, world!";
  };

  testNoLib = {
    expr = (discover.discoverAll (fixtures + "/empty")).lib;
    expected = null;
  };

  testPlainLib = {
    expr =
      let
        libPath = (discover.discoverAll (fixtures + "/plain-lib")).lib;
        lib = importLib libPath {};
      in
      lib.add 1 2;
    expected = 3;
  };
}
