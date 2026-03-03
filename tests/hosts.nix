# Tests for host building
let
  prelude = import ./prelude.nix;
  inherit (prelude) discover builders fixtures;
  inherit (builders) buildHosts;

  fullHosts = (discover.discoverAll (fixtures + "/full")).hosts;

  testResult = buildHosts {
    discovered = { inherit (fullHosts) custom; };
  };
in
{
  testCustomHostLoaded = {
    expr = testResult.nixosConfigurations.custom.value._type;
    expected = "test-nixos-system";
  };

  testCustomHostName = {
    expr = testResult.nixosConfigurations.custom.value.hostName;
    expected = "custom";
  };

  testEmptyHosts = {
    expr =
      let
        result = buildHosts { discovered = { }; };
      in
      {
        hasAutoChecks = builtins.isFunction result.autoChecks;
        noOutputKeys = builtins.attrNames (builtins.removeAttrs result [ "autoChecks" ]);
      };
    expected = {
      hasAutoChecks = true;
      noOutputKeys = [ ];
    };
  };

  testHostDiscoveryTypes = {
    expr =
      let
        hosts = (discover.discoverAll (fixtures + "/full")).hosts;
      in
      {
        myhost = hosts.myhost.type;
        custom = hosts.custom.type;
      };
    expected = {
      myhost = "nixos";
      custom = "custom";
    };
  };
}
