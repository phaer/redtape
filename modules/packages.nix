# /packages — Per-system package builder
#
# Each .nix file receives: { pkgs, system, pname, lib, ... }

{ types, ... }:
let
  inherit (builtins) mapAttrs;

  callFile = import ../lib/call-file.nix;
  filterPlatforms = import ../lib/filter-platforms.nix;
in
{
  name = "packages";

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
      system = inputs.nixpkgs.system;
      pkgs = inputs.nixpkgs.pkgs;

      scope = {
        inherit pkgs system;
        lib = pkgs.lib;
      } // options.extraScope;

      buildPkg = pname: entry:
        let path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
        in callFile scope path { inherit pname; };

      allPackages = mapAttrs buildPkg options.discovered;
    in
    {
      packages = allPackages;
      filteredPackages = filterPlatforms system allPackages;
    };
}
