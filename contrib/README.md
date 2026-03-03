# red-tape contrib modules

Optional adios-flake modules for output types outside red-tape's minimal core.
Pass them via `modules` in your `mkFlake` call.

## Available modules

| Module | File | Scans for | Produces |
|--------|------|-----------|----------|
| system-manager | `system-manager.nix` | `hosts/*/system-configuration.nix` | `systemConfigs.*` |

## Usage

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url        = "github:NixOS/nixpkgs/nixos-unstable";
    system-manager.url = "github:numtide/system-manager";
    red-tape.url       = "github:phaer/red-tape";
  };

  outputs = inputs:
    inputs.red-tape.mkFlake {
      inherit inputs;
      extraModules = [
        (import (inputs.red-tape + "/contrib/system-manager.nix") {
          inherit inputs;
          src = inputs.self;
        })
      ];
    };
}
```

Then put your system-manager configs in `hosts/<name>/system-configuration.nix`.

## Writing your own

A contrib module is a standard adios-flake ergonomic function module.
Import `nix/discover.nix` directly for host-type or directory scanning:

```nix
# Example: nix-on-droid support
{ inputs, src }:
let
  discover = import (inputs.red-tape + "/nix/discover.nix");
  discovered = discover.scanHosts (src + "/hosts") [
    { type = "nix-on-droid"; file = "droid-configuration.nix"; }
  ];
in
{ self, ... }:
{
  nixOnDroidConfigurations = builtins.mapAttrs (hostName: hostInfo:
    inputs.nix-on-droid.lib.nixOnDroidConfiguration {
      pkgs = import inputs.nixpkgs { system = "aarch64-linux"; };
      modules = [ hostInfo.configPath ];
      extraSpecialArgs = { flake = self; inherit hostName; };
    }
  ) discovered;
}
```
