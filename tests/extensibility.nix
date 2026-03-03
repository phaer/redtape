let
  prelude = import ./prelude.nix;
  inherit (prelude)
    discover
    helpers
    builders
    fixtures
    ;
  inherit (helpers) entryPath;
  inherit (builders) buildModules;
  inherit (discover) scanDir scanHosts;
in
{
  testScanCustomHostType = {
    expr =
      let
        found = scanHosts (fixtures + "/custom-hosts/hosts") [
          {
            type = "nix-on-droid";
            file = "droid-configuration.nix";
          }
        ];
      in
      {
        names = builtins.attrNames found;
        type = found.myphone.type;
      };
    expected = {
      names = [ "myphone" ];
      type = "nix-on-droid";
    };
  };
  testCoreHostTypesIgnoreCustom = {
    expr = (discover.discoverAll (fixtures + "/custom-hosts")).hosts;
    expected = { };
  };
  testScanHostsFirstMatchWins = {
    expr =
      let
        found = scanHosts (fixtures + "/full/hosts") [
          {
            type = "custom";
            file = "default.nix";
          }
          {
            type = "nixos";
            file = "configuration.nix";
          }
        ];
      in
      {
        customType = found.custom.type;
        myhostType = found.myhost.type;
      };
    expected = {
      customType = "custom";
      myhostType = "nixos";
    };
  };
}
