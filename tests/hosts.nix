# Tests for host building
let
  prelude = import ./prelude.nix;
  inherit (prelude) _internal fixtures;
  inherit (_internal) discover;
  inherit (_internal.builders) buildHosts;

  fullHosts = (discover.discoverAll (fixtures + "/full")).hosts;

  testResult = buildHosts {
    discovered = { inherit (fullHosts) custom mymac; };
    allInputs = {};
    self = null;
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
    expr =
      let result = buildHosts { discovered = {}; allInputs = {}; self = null; };
      in {
        inherit (result) nixosConfigurations darwinConfigurations;
        hasAutoChecks = builtins.isFunction result.autoChecks;
      };
    expected = {
      nixosConfigurations = {};
      darwinConfigurations = {};
      hasAutoChecks = true;
    };
  };

  testHostDiscoveryTypes = {
    expr =
      let hosts = (discover.discoverAll (fixtures + "/full")).hosts;
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
