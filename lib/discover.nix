# discover.nix — Pure filesystem scanning
#
# Expected project layout:
#
#   src/
#   ├── package.nix | packages/{name}.nix | packages/{name}/default.nix
#   ├── devshell.nix | devshells/{name}.nix
#   ├── formatter.nix
#   ├── checks/{name}.nix
#   ├── overlays/{name}.nix | overlay.nix
#   ├── hosts/{name}/configuration.nix  (nixos)
#   │               /darwin-configuration.nix  (darwin)
#   │               /default.nix  (custom)
#   ├── modules/{type}/{name}.nix
#   ├── templates/{name}/flake.nix
#   └── lib/default.nix
#
let
  inherit (builtins)
    attrNames
    filter
    head
    listToAttrs
    map
    match
    pathExists
    readDir
    ;

  # ── Core primitive ─────────────────────────────────────────────────

  # Scan a directory for .nix files and subdirectories with default.nix.
  # Returns { name = { path; type = "file"|"directory"; }; ... }
  # .nix files take precedence over directories with the same stem.
  scanDir =
    path:
    if !pathExists path then
      { }
    else
      let
        entries = readDir path;
        dirs = listToAttrs (
          filter (x: x != null) (
            map (
              name:
              if entries.${name} == "directory" && pathExists (path + "/${name}/default.nix") then
                {
                  inherit name;
                  value = {
                    path = path + "/${name}";
                    type = "directory";
                  };
                }
              else
                null
            ) (attrNames entries)
          )
        );
        files = listToAttrs (
          filter (x: x != null) (
            map (
              name:
              let
                m = match "(.+)\\.nix$" name;
              in
              if entries.${name} == "regular" && m != null && name != "default.nix" then
                {
                  name = head m;
                  value = {
                    path = path + "/${name}";
                    type = "file";
                  };
                }
              else
                null
            ) (attrNames entries)
          )
        );
      in
      dirs // files;

in
{
  inherit scanDir;
}
