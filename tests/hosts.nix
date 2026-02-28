# Tests for host building
let
  discover = import ../modules/discover.nix;
  fixtures = ../tests/fixtures;

  buildHosts = import ../lib/build-hosts.nix {
    flakeInputs = {};
    self = null;
  };

  fullHosts = (discover (fixtures + "/full")).hosts;

  # Both custom and mymac use the escape hatch (avoids real nixpkgs/nix-darwin)
  testHosts = buildHosts {
    inherit (fullHosts) custom mymac;
  };
in
{
  testCustomHostLoaded = {
    expr = testHosts.nixosConfigurations.custom._type;
    expected = "test-nixos-system";
  };

  testCustomHostName = {
    expr = testHosts.nixosConfigurations.custom.hostName;
    expected = "custom";
  };

  testDarwinHostLoaded = {
    expr = testHosts.darwinConfigurations.mymac._type;
    expected = "test-darwin-system";
  };

  testDarwinHostName = {
    expr = testHosts.darwinConfigurations.mymac.hostName;
    expected = "mymac";
  };

  # nixos and darwin are separated correctly
  testDarwinNotInNixos = {
    expr = testHosts.nixosConfigurations ? mymac;
    expected = false;
  };

  testNixosNotInDarwin = {
    expr = testHosts.darwinConfigurations ? custom;
    expected = false;
  };

  testEmptyHosts = {
    expr = buildHosts {};
    expected = {
      nixosConfigurations = {};
      darwinConfigurations = {};
    };
  };

  testHostDiscoveryTypes = {
    expr =
      let hosts = (discover (fixtures + "/full")).hosts;
      in {
        myhost = hosts.myhost.type;
        mymac = hosts.mymac.type;
        custom = hosts.custom.type;
      };
    expected = {
      myhost = "nixos";
      mymac = "custom";  # uses default.nix escape hatch
      custom = "custom";
    };
  };
}
