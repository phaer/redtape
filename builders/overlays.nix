# builders/overlays.nix — Build overlays from discovered entries
#
# Overlays are system-agnostic (final: prev: { ... }).
# The .nix files receive { lib, flake, inputs, ... } but NOT pkgs or system.
#
# Returns: { overlays = { <name> = <overlay-fn>; ... }; }
{ callFile }:
{ discovered, scope }:
let
  inherit (builtins) mapAttrs;
in
{
  overlays = mapAttrs (pname: entry:
    let path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
    in callFile scope path { inherit pname; }
  ) discovered;
}
