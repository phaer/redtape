# discover.nix — Pure filesystem scanning
#
# Expected project layout:
#
#   src/
#   ├── package.nix | packages/{name}.nix | packages/{name}/default.nix
#   ├── devshell.nix | devshells/{name}.nix
#   ├── formatter.nix
#   ├── checks/{name}.nix
#   ├── hosts/{name}/configuration.nix  (nixos)
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

  # ── Derived scanners ───────────────────────────────────────────────

  # Like scanDir but for hosts: walks subdirs looking for sentinel files
  # (e.g. configuration.nix) to determine host type.
  # Returns { name = { type; configPath; hostPath; }; ... }.
  scanHosts =
    path: hostTypes:
    if !pathExists path then
      { }
    else
      let
        entries = readDir path;
      in
      listToAttrs (
        filter (x: x != null) (
          map (
            name:
            if entries.${name} != "directory" then
              null
            else
              let
                hostPath = path + "/${name}";
                hits = filter (t: pathExists (hostPath + "/${t.file}")) hostTypes;
              in
              if hits == [ ] then
                null
              else
                {
                  inherit name;
                  value = {
                    type = (head hits).type;
                    configPath = hostPath + "/${(head hits).file}";
                    inherit hostPath;
                  };
                }
          ) (attrNames entries)
        )
      );

  # Host type sentinels — checked in order, first match wins.
  coreHostTypes = [
    {
      type = "custom";
      file = "default.nix";
    }
    {
      type = "nixos";
      file = "configuration.nix";
    }
  ];

  # ── Whole-tree discovery ───────────────────────────────────────────

  optional =
    path:
    let
      v = scanDir path;
    in
    if v == { } then { } else v;

  # scanDir skips bare default.nix in the scanned directory itself.
  # optionalDefault adds it back as the "default" entry when present.
  optionalDefault =
    path:
    if pathExists (path + "/default.nix") then
      {
        default = {
          path = path + "/default.nix";
          type = "file";
        };
      }
    else
      { };

  optionalSingle =
    path: name:
    if pathExists path then
      {
        ${name} = {
          inherit path;
          type = "file";
        };
      }
    else
      { };

  discoverAll = src: {
    packages =
      optionalDefault (src + "/packages")
      // optional (src + "/packages")
      // optionalSingle (src + "/package.nix") "default";
    devshells =
      optionalDefault (src + "/devshells")
      // optional (src + "/devshells")
      // optionalSingle (src + "/devshell.nix") "default";
    checks = optionalDefault (src + "/checks") // optional (src + "/checks");
    hosts = scanHosts (src + "/hosts") coreHostTypes;
    formatter = if pathExists (src + "/formatter.nix") then src + "/formatter.nix" else null;
    templates =
      if !pathExists (src + "/templates") then
        { }
      else
        let
          e = readDir (src + "/templates");
        in
        listToAttrs (
          map (n: {
            name = n;
            value = {
              path = src + "/templates/${n}";
            };
          }) (filter (n: e.${n} == "directory") (attrNames e))
        );
    modules =
      let
        p = src + "/modules";
      in
      if !pathExists p then
        { }
      else
        let
          e = readDir p;
        in
        listToAttrs (
          map (n: {
            name = n;
            value = scanDir (p + "/${n}");
          }) (filter (n: e.${n} == "directory") (attrNames e))
        );
    lib =
      let
        p = src + "/lib/default.nix";
      in
      if pathExists p then p else null;
  };

in
{
  inherit
    scanDir
    scanHosts
    coreHostTypes
    discoverAll
    ;
}
