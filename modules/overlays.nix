# /overlays — System-agnostic overlay builder
#
# No /nixpkgs dependency — overlays are functions (final: prev: { ... }),
# not derivations. Evaluated once by adios, memoized across system overrides.
#
# Files may accept { lib, flake, inputs, ... } but NOT pkgs/system
# (overlays receive their own pkgs via final/prev at application time).

{ types, ... }:
let
  callFile = import ../lib/call-file.nix;
in
{
  name = "overlays";

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

  impl = { options, ... }:
    let
      scope = options.extraScope;

      buildOverlay = pname: entry:
        let path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
        in callFile scope path { inherit pname; };
    in
    {
      overlays = builtins.mapAttrs buildOverlay options.discovered;
    };
}
