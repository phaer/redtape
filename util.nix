# util.nix — Shared utilities
let
  inherit (builtins) attrNames elem filter listToAttrs map;
in
{
  # Prefix all keys in an attrset.
  withPrefix = prefix: attrs:
    listToAttrs (map (name: {
      name = "${prefix}${name}";
      value = attrs.${name};
    }) (attrNames attrs));

  # Filter packages by meta.platforms for the given system.
  # Packages with no meta.platforms are kept.
  filterPlatforms = system: packages:
    listToAttrs (filter (x: x != null) (map (name:
      let
        pkg = packages.${name};
        platforms = pkg.meta.platforms or [];
      in
      if platforms == [] || elem system platforms
      then { inherit name; value = pkg; }
      else null
    ) (attrNames packages)));
}
