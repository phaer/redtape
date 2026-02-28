# Tests for host building
let
  discover = import ../modules/discover.nix;
  fixtures = ../tests/fixtures;

  buildHosts = import ../lib/build-hosts.nix {
    flakeInputs = {};
    self = null;
  };

  # Only test the custom host — nixos/darwin need real nixpkgs
  customOnly = buildHosts {
    custom = (discover (fixtures + "/full")).hosts.custom;
  };
in
{
  testCustomHostLoaded = {
    expr = customOnly.nixosConfigurations.custom._type;
    expected = "test-nixos-system";
  };

  testCustomHostName = {
    expr = customOnly.nixosConfigurations.custom.hostName;
    expected = "custom";
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
        custom = hosts.custom.type;
      };
    expected = {
      myhost = "nixos";
      custom = "custom";
    };
  };
}
