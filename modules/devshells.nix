# /devshells — Per-system devshell builder
#
# Each .nix file receives: { pkgs, system, pname, lib, ... }

{ types, ... }:
let
  inherit (builtins) mapAttrs;

  callFile = import ../lib/call-file.nix;
in
{
  name = "devshells";

  inputs = {
    nixpkgs = { path = "/nixpkgs"; };
  };

  options = {
    discovered = {
      type = types.attrs;
      default = {};
    };
    extraScope = {
      type = types.attrs;
      default = {};
    };
  };

  impl = { inputs, options, ... }:
    let
      scope = {
        pkgs = inputs.nixpkgs.pkgs;
        system = inputs.nixpkgs.system;
        lib = inputs.nixpkgs.pkgs.lib;
      } // options.extraScope;

      buildShell = pname: entry:
        let path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
        in callFile scope path { inherit pname; };
    in
    {
      devShells = mapAttrs buildShell options.discovered;
    };
}
