# Tests for lib export
let
  prelude = import ./prelude.nix;
  inherit (prelude) _internal fixtures;
  inherit (_internal) discover;
  inherit (_internal.builders) importLib;
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
        lib = importLib { inherit libPath; flake = null; inputs = {}; };
      in
      lib.greet "world";
    expected = "Hello, world!";
  };

  testNoLib = {
    expr = (discover.discoverAll (fixtures + "/empty")).lib;
    expected = null;
  };

  # Plain attrset lib (no { flake, inputs } wrapper)
  testPlainLib = {
    expr =
      let
        libPath = (discover.discoverAll (fixtures + "/plain-lib")).lib;
        lib = importLib { inherit libPath; };
      in
      lib.add 1 2;
    expected = 3;
  };
}
