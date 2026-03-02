# builders/templates.nix — Build template descriptions from discovered entries
#
# Returns: { <name> = { path; description; }; ... }
discovered:
let
  inherit (builtins) mapAttrs pathExists;
in
mapAttrs (name: entry:
  let flakeNix = entry.path + "/flake.nix";
  in {
    inherit (entry) path;
    description =
      if pathExists flakeNix then (import flakeNix).description or name
      else name;
  }
) discovered
