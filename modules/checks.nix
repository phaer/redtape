# /checks — Per-system check builder
#
# Only handles user-defined checks from the checks/ directory.
# Auto-checks from packages and devshells are assembled by the entry point.

{ types, ... }:
let
  inherit (builtins) mapAttrs;

  callFile = import ../lib/call-file.nix;
  filterPlatforms = import ../lib/filter-platforms.nix;
in
{
  name = "checks";

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

      scope = {
        pkgs = inputs.nixpkgs.pkgs;
        inherit system;
        lib = inputs.nixpkgs.pkgs.lib;
      } // options.extraScope;

      userChecks = filterPlatforms system (mapAttrs (pname: entry:
        let path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
        in callFile scope path { inherit pname; }
      ) options.discovered);
    in
    {
      checks = userChecks;
    };
}
