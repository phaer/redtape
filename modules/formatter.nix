# /formatter — Per-system formatter
#
# Imports formatter.nix if discovered, otherwise falls back to nixfmt-tree.

{ types, ... }:
let
  callFile = import ../lib/call-file.nix;
in
{
  name = "formatter";

  inputs = {
    nixpkgs = { path = "/nixpkgs"; };
  };

  options = {
    formatterPath = {
      type = types.any;
      default = null;
    };
    extraScope = {
      type = types.attrs;
      default = {};
    };
  };

  impl = { inputs, options, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;

      scope = {
        inherit pkgs;
        system = inputs.nixpkgs.system;
        lib = pkgs.lib;
      } // options.extraScope;
    in
    {
      formatter =
        if options.formatterPath != null then
          callFile scope options.formatterPath {}
        else
          pkgs.nixfmt-tree or pkgs.nixfmt or
            (throw "red-tape: no formatter.nix found and nixfmt-tree is not available in nixpkgs");
    };
}
