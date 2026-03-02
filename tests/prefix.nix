# Tests for prefix support
let
  prelude = import ./prelude.nix;
  inherit (prelude) _internal fixtures;
  inherit (_internal) discover;
in
{
  # Discover sees packages when pointed at the prefix subdirectory
  testPrefixDiscovery = {
    expr = builtins.sort builtins.lessThan
      (builtins.attrNames (discover.discoverAll (fixtures + "/prefixed/nix")).packages);
    expected = [ "default" "widget" ];
  };

  # Discover at the wrong root sees nothing
  testNoPrefixMissesPackages = {
    expr = (discover.discoverAll (fixtures + "/prefixed")).packages;
    expected = {};
  };
}
