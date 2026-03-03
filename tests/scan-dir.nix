# Tests for scanDir
let
  discover = import ../lib/discover.nix;
  inherit (discover) scanDir;
  fixtures = ../tests/fixtures;
  full = fixtures + "/full";
in
{
  testPackages = {
    expr = builtins.attrNames (scanDir (full + "/packages"));
    expected = [
      "goodbye"
      "hello"
    ];
  };

  testFileType = {
    expr = (scanDir (full + "/packages")).hello.type;
    expected = "file";
  };

  testDirType = {
    expr = (scanDir (full + "/packages")).goodbye.type;
    expected = "directory";
  };

  testDevshells = {
    expr = builtins.attrNames (scanDir (full + "/devshells"));
    expected = [ "backend" ];
  };

  testNonExistent = {
    expr = scanDir (full + "/nonexistent");
    expected = { };
  };

  testEmpty = {
    expr = scanDir (fixtures + "/empty");
    expected = { };
  };

  testChecks = {
    expr = builtins.attrNames (scanDir (full + "/checks"));
    expected = [ "mycheck" ];
  };
}
