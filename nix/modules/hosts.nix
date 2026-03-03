# red-tape/hosts — Build NixOS/Darwin host configurations
#
# Inputs: ../scan (discovery + flake context)
# Result: { nixosConfigurations, darwinConfigurations, autoChecks }
#
# autoChecks is a function system → { name = toplevel; } consumed by ../checks.
# nixosConfigurations and darwinConfigurations are flake-scoped.
{ buildHosts }:

{
  name = "hosts";
  inputs = {
    scan = { path = "../scan"; };
  };
  impl = { results, ... }:
    let
      inherit (results.scan) discovered self allInputs;
    in
    if discovered.hosts != {} then
      buildHosts { discovered = discovered.hosts; inherit allInputs self; }
    else
      { nixosConfigurations = {}; darwinConfigurations = {}; autoChecks = _: {}; };
}
