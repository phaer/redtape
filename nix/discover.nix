# discover.nix — Pure filesystem scanning
#
# All functions are pure: they take paths, return data describing what's on disk.
# No evaluation, no pkgs, no adios — just builtins.readDir + builtins.pathExists.
let
  inherit (builtins) attrNames filter head listToAttrs map match pathExists readDir;

  # ── Core primitive ─────────────────────────────────────────────────

  # Scan a directory for .nix files and subdirectories with default.nix.
  # Returns { name = { path; type = "file"|"directory"; }; ... }
  # .nix files take precedence over directories with the same stem.
  scanDir = path:
    if !pathExists path then {}
    else let
      entries = readDir path;
      dirs = listToAttrs (filter (x: x != null) (map (name:
        if entries.${name} == "directory" && pathExists (path + "/${name}/default.nix")
        then { inherit name; value = { path = path + "/${name}"; type = "directory"; }; }
        else null
      ) (attrNames entries)));
      files = listToAttrs (filter (x: x != null) (map (name:
        let m = match "(.+)\\.nix$" name;
        in if entries.${name} == "regular" && m != null && name != "default.nix"
        then { name = head m; value = { path = path + "/${name}"; type = "file"; }; }
        else null
      ) (attrNames entries)));
    in dirs // files;

  # ── Derived scanners ───────────────────────────────────────────────

  # Scan host subdirectories for sentinel files.  First match wins per host.
  scanHosts = path: hostTypes:
    if !pathExists path then {}
    else let
      entries = readDir path;
    in listToAttrs (filter (x: x != null) (map (name:
      if entries.${name} != "directory" then null
      else let
        hostPath = path + "/${name}";
        hits = filter (t: pathExists (hostPath + "/${t.file}")) hostTypes;
      in if hits == [] then null
        else { inherit name; value = { type = (head hits).type; configPath = hostPath + "/${(head hits).file}"; inherit hostPath; }; }
    ) (attrNames entries)));

  # Host type sentinels — checked in order, first match wins.
  coreHostTypes = [
    { type = "custom"; file = "default.nix"; }
    { type = "nixos";  file = "configuration.nix"; }
    { type = "darwin"; file = "darwin-configuration.nix"; }
  ];

  # ── Whole-tree discovery ───────────────────────────────────────────

  optional = path: let v = scanDir path; in if v == {} then {} else v;

  optionalSingle = path: name:
    if pathExists path then { ${name} = { inherit path; type = "file"; }; } else {};

  discoverAll = src: {
    packages  = optional (src + "/packages")  // optionalSingle (src + "/package.nix") "default";
    devshells = optional (src + "/devshells")  // optionalSingle (src + "/devshell.nix") "default";
    checks    = optional (src + "/checks");
    overlays  = optional (src + "/overlays")   // optionalSingle (src + "/overlay.nix") "default";
    hosts     = scanHosts (src + "/hosts") coreHostTypes;
    formatter = if pathExists (src + "/formatter.nix") then src + "/formatter.nix" else null;
    templates = if !pathExists (src + "/templates") then {}
      else let e = readDir (src + "/templates");
      in listToAttrs (map (n: { name = n; value = { path = src + "/templates/${n}"; }; })
        (filter (n: e.${n} == "directory") (attrNames e)));
    modules   = let p = src + "/modules"; in
      if !pathExists p then {}
      else let e = readDir p;
      in listToAttrs (map (n: { name = n; value = scanDir (p + "/${n}"); })
        (filter (n: e.${n} == "directory") (attrNames e)));
    lib       = let p = src + "/lib/default.nix"; in if pathExists p then p else null;
  };

in { inherit scanDir scanHosts coreHostTypes discoverAll; }
