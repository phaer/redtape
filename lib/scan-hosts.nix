# scan-hosts.nix — Scan hosts/ directory structure
#
# Returns: { hostname = { path, type, hostPath }; ... }
#
# Config type determined by filename:
#   configuration.nix        → "nixos"
#   darwin-configuration.nix → "darwin"
#   default.nix              → "custom"  (user escape hatch)

let
  inherit (builtins)
    attrNames
    filter
    listToAttrs
    pathExists
    readDir
    ;

  detectConfigType = hostPath:
    if pathExists (hostPath + "/default.nix") then
      { type = "custom"; path = hostPath + "/default.nix"; }
    else if pathExists (hostPath + "/configuration.nix") then
      { type = "nixos"; path = hostPath + "/configuration.nix"; }
    else if pathExists (hostPath + "/darwin-configuration.nix") then
      { type = "darwin"; path = hostPath + "/darwin-configuration.nix"; }
    else
      null;

in
path:
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
        in
        if config != null then {
          inherit name;
          value = {
            inherit (config) type path;
            hostPath = hostPath;
          };
        }
        else null
    ) names))
