# discover.nix — Pure filesystem scanning
#
# All functions are pure: they take paths, return data describing what's on disk.
# No evaluation, no pkgs, no adios — just builtins.readDir + builtins.pathExists.
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

  matchNixFile = match "(.+)\\.nix$";

  # Scan a directory for .nix files and subdirectories with default.nix.
  # Returns { name = { path; type = "file"|"directory"; }; ... }
  # .nix files take precedence over directories with the same stem.
  scanDir = path:
    if !pathExists path then {}
    else
      let
        entries = readDir path;
        names = attrNames entries;
        nixFiles = listToAttrs (filter (x: x != null) (map (name:
          let m = matchNixFile name;
          in if entries.${name} == "regular" && m != null && name != "default.nix"
          then { name = head m; value = { path = path + "/${name}"; type = "file"; }; }
          else null
        ) names));
        dirs = listToAttrs (filter (x: x != null) (map (name:
          if entries.${name} == "directory" && pathExists (path + "/${name}/default.nix")
          then { inherit name; value = { path = path + "/${name}"; type = "directory"; }; }
          else null
        ) names));
      in
      dirs // nixFiles;

  # Scan hosts/ subdirectories for files matching a list of { type; file }.
  # Checked in order — first match wins per host directory.
  scanHosts = path: hostTypes:
    if !pathExists path then {}
    else
      let
        entries = readDir path;
        detectType = hostPath:
          let matches = filter (t: pathExists (hostPath + "/${t.file}")) hostTypes;
          in if matches == [] then null
             else let t = head matches;
                  in { type = t.type; configPath = hostPath + "/${t.file}"; };
      in
      listToAttrs (filter (x: x != null) (map (name:
        if entries.${name} != "directory" then null
        else let hostPath = path + "/${name}"; config = detectType hostPath;
        in if config != null
          then { inherit name; value = config // { inherit hostPath; }; }
          else null
      ) (attrNames entries)));

  # Scan modules/<type>/ directories for re-export.
  scanModuleTypes = path:
    if !pathExists path then {}
    else
      let entries = readDir path;
      in listToAttrs (map (typeName: {
        name = typeName;
        value = scanDir (path + "/${typeName}");
      }) (filter (n: entries.${n} == "directory") (attrNames entries)));

  # Scan templates/ for subdirectories.
  scanTemplates = path:
    if !pathExists path then {}
    else
      let entries = readDir path;
      in listToAttrs (map (name: {
        inherit name;
        value = { path = path + "/${name}"; };
      }) (filter (n: entries.${n} == "directory") (attrNames entries)));

  optionalFile = path: name:
    if pathExists path then { ${name} = { inherit path; type = "file"; }; } else {};

  optionalPath = path:
    if pathExists path then path else null;

  # Host type sentinels — checked in order, first match wins.
  coreHostTypes = [
    { type = "custom"; file = "default.nix"; }
    { type = "nixos";  file = "configuration.nix"; }
    { type = "darwin"; file = "darwin-configuration.nix"; }
  ];

  # Run all discovery on a source tree. Returns a flat attrset of what was found.
  # Each key is present only if something was found; absent keys mean "nothing here".
  discoverAll = src: {
    packages =
      let v = scanDir (src + "/packages") // optionalFile (src + "/package.nix") "default";
      in if v == {} then null else v;

    devshells =
      let v = scanDir (src + "/devshells") // optionalFile (src + "/devshell.nix") "default";
      in if v == {} then null else v;

    checks =
      let v = scanDir (src + "/checks");
      in if v == {} then null else v;

    overlays =
      let v = scanDir (src + "/overlays") // optionalFile (src + "/overlay.nix") "default";
      in if v == {} then null else v;

    hosts =
      let v = scanHosts (src + "/hosts") coreHostTypes;
      in if v == {} then null else v;

    modules =
      let v = scanModuleTypes (src + "/modules");
      in if v == {} then null else v;

    formatter = optionalPath (src + "/formatter.nix");
    templates = scanTemplates (src + "/templates");
    lib       = optionalPath (src + "/lib/default.nix");
  };

in
{
  inherit
    scanDir
    scanHosts
    scanModuleTypes
    scanTemplates
    optionalFile
    optionalPath
    coreHostTypes
    discoverAll
    ;
}
