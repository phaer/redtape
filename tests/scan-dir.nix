# Tests for scanDir
let
  prelude = import ./prelude.nix;
  inherit (prelude) _internal fixtures;
  inherit (_internal.discover) scanDir;
in
{
  # Discovers .nix files and directories with default.nix
  testSimplePackages = {
    expr =
      let result = scanDir (fixtures + "/simple/packages");
      in builtins.attrNames result;
    expected = [ "goodbye" "hello" ];
  };

  # .nix file is detected as type "file"
  testFileType = {
    expr = (scanDir (fixtures + "/simple/packages")).hello.type;
    expected = "file";
  };

  # Directory is detected as type "directory"
  testDirType = {
    expr = (scanDir (fixtures + "/simple/packages")).goodbye.type;
    expected = "directory";
  };

  # Named devshells are discovered
  testDevshells = {
    expr = builtins.attrNames (scanDir (fixtures + "/simple/devshells"));
    expected = [ "backend" ];
  };

  # Non-existent directory returns empty
  testNonExistent = {
    expr = scanDir (fixtures + "/simple/nonexistent");
    expected = {};
  };

  # Empty directory returns empty
  testEmpty = {
    expr = scanDir (fixtures + "/empty");
    expected = {};
  };

  # Checks directory
  testChecks = {
    expr = builtins.attrNames (scanDir (fixtures + "/simple/checks"));
    expected = [ "mycheck" ];
  };
}
