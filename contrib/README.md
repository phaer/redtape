# red-tape contrib modules

Optional adios-flake modules for output types outside red-tape's minimal core.
Pass them via `modules` in your `mkFlake` call.

## Available modules

| Module | File | Scans for | Produces |
|--------|------|-----------|----------|
| system-manager | `system-manager.nix` | `hosts/*/system-configuration.nix` | `systemConfigs.*` |

## How it works

Contrib modules are standard **adios-flake modules** — they return flake
output attrsets just like any `perSystem` or `flake` function. Each module
independently scans the `hosts/` directory for its own sentinel files.
The core hosts builder finds `configuration.nix` and
`darwin-configuration.nix`; the system-manager module finds
`system-configuration.nix`. No conflicts.

## Usage

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url        = "github:NixOS/nixpkgs/nixos-unstable";
    system-manager.url = "github:numtide/system-manager";
    red-tape.url       = "github:you/red-tape";
  };

  outputs = inputs:
    let rt = inputs.red-tape;
    in rt.mkFlake {
      inherit inputs;
      modules = [
        (import (rt + "/contrib/system-manager.nix") {
          inherit inputs;
          src = inputs.self;
          scanHosts = rt.lib._internal.discover.scanHosts;
        })
      ];
    };
}
```

Then put your system-manager configs in `hosts/<name>/system-configuration.nix`.

## Writing your own

A contrib module is just a standard adios-flake module — either an ergonomic
function or a native adios module. Use `red-tape.lib._internal.discover.scanHosts`
for host-type scanning or `red-tape.lib._internal.discover.scanDir` for generic
directory scanning.

```nix
# Example: nix-on-droid support
{ inputs, src, scanHosts }:
let
  discovered = scanHosts (src + "/hosts") [
    { type = "nix-on-droid"; file = "droid-configuration.nix"; }
  ];
in
{ self, ... }:
{
  nixOnDroidConfigurations = builtins.mapAttrs (hostName: hostInfo:
    inputs.nix-on-droid.lib.nixOnDroidConfiguration {
      pkgs = import inputs.nixpkgs { system = "aarch64-linux"; };
      modules = [ hostInfo.configPath ];
      extraSpecialArgs = { flake = self; inherit (inputs) inputs; inherit hostName; };
    }
  ) discovered;
}
```
