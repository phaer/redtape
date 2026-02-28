# Tests for host building via adios module
let
  prelude = import ./prelude.nix;
  inherit (prelude) adios fixtures;

  discover = import ../modules/discover.nix;
  callMod = path: import path adios;

  fullHosts = (discover (fixtures + "/full")).hosts;

  # Evaluate the hosts module directly
  evalHosts = discoveredHosts:
    let
      loaded = adios {
        name = "hosts-test";
        modules = {
          hosts = callMod ../modules/hosts.nix;
        };
      };
      evaled = loaded {
        options = {
          "/hosts" = {
            discovered = discoveredHosts;
            flakeInputs = {};
            self = null;
          };
        };
      };
    in
    evaled.modules.hosts {};

  # Both custom and mymac use the escape hatch
  testResult = evalHosts {
    inherit (fullHosts) custom mymac;
  };
in
{
  testCustomHostLoaded = {
    expr = testResult.nixosConfigurations.custom._type;
    expected = "test-nixos-system";
  };

  testCustomHostName = {
    expr = testResult.nixosConfigurations.custom.hostName;
    expected = "custom";
  };

  testDarwinHostLoaded = {
    expr = testResult.darwinConfigurations.mymac._type;
    expected = "test-darwin-system";
  };

  testDarwinHostName = {
    expr = testResult.darwinConfigurations.mymac.hostName;
    expected = "mymac";
  };

  testDarwinNotInNixos = {
    expr = testResult.nixosConfigurations ? mymac;
    expected = false;
  };

  testNixosNotInDarwin = {
    expr = testResult.darwinConfigurations ? custom;
    expected = false;
  };

  testEmptyHosts = {
    expr = evalHosts {};
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
      mymac = "custom";
      custom = "custom";
    };
  };
}
