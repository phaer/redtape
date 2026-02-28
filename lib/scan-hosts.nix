# scan-hosts.nix — Scan hosts/ directory structure
#
# Returns: { hostname = { path, configType, users }; ... }
#
# configType is determined by which file exists:
#   configuration.nix      → "nixos"
#   darwin-configuration.nix → "darwin"
#   system-configuration.nix → "system-manager"
#   rpi-configuration.nix  → "rpi"
#   default.nix            → "custom"  (user escape hatch)
#
# users: { username = path; ... } from hosts/<name>/users/

let
  inherit (builtins)
    attrNames
    filter
    head
    listToAttrs
    match
    pathExists
    readDir
    ;

  matchNixFile = match "(.+)\\.nix$";

  # Scan users directory for a host
  scanUsers = hostPath:
    let
      usersPath = hostPath + "/users";
    in
    if !pathExists usersPath then
      {}
    else
      let
        entries = readDir usersPath;
        names = attrNames entries;
      in
      listToAttrs (filter (x: x != null) (map (name:
        if entries.${name} == "directory" then
          let homeCfg = usersPath + "/${name}/home-configuration.nix";
          in
          if pathExists homeCfg then
            { inherit name; value = homeCfg; }
          else
            null
        else
          let m = matchNixFile name;
          in
          if m != null && name != "default.nix" then
            { name = head m; value = usersPath + "/${name}"; }
          else
            null
      ) names));

  # Determine host config type from files present
  detectConfigType = hostPath:
    if pathExists (hostPath + "/default.nix") then
      { type = "custom"; path = hostPath + "/default.nix"; }
    else if pathExists (hostPath + "/configuration.nix") then
      { type = "nixos"; path = hostPath + "/configuration.nix"; }
    else if pathExists (hostPath + "/darwin-configuration.nix") then
      { type = "darwin"; path = hostPath + "/darwin-configuration.nix"; }
    else if pathExists (hostPath + "/system-configuration.nix") then
      { type = "system-manager"; path = hostPath + "/system-configuration.nix"; }
    else if pathExists (hostPath + "/rpi-configuration.nix") then
      { type = "rpi"; path = hostPath + "/rpi-configuration.nix"; }
    else
      null;

  scanHosts = path:
    if !pathExists path then
      {}
    else
      let
        entries = readDir path;
        names = attrNames entries;
      in
      listToAttrs (filter (x: x != null) (map (name:
        if entries.${name} != "directory" then null
        else
          let
            hostPath = path + "/${name}";
            config = detectConfigType hostPath;
            users = scanUsers hostPath;
          in
          if config != null then
            {
              inherit name;
              value = {
                inherit (config) type path;
                hostPath = hostPath;
                inherit users;
              };
            }
          # Host dir with only users (standalone home-manager) — no host config
          else if users != {} then
            {
              inherit name;
              value = {
                type = "home-only";
                path = null;
                hostPath = hostPath;
                inherit users;
              };
            }
          else
            null
      ) names));

in
scanHosts
