# discover.nix — Filesystem discovery (pure function, not an adios module)
#
# Scans the project source tree and returns paths to discovered files.
# Does NOT import anything — actual imports happen in per-system modules
# or in the entry point for system-agnostic outputs.
#
# This is a plain function, not an adios module, because:
# - It has no dependencies on other modules
# - Its results need to be passed as options to per-system modules
# - In adios, data flows through options, not impl results

let
  scanDir = import ../lib/scan-dir.nix;
  scanHosts = import ../lib/scan-hosts.nix;

  inherit (builtins) pathExists readDir attrNames filter listToAttrs;

  # Return a single-entry attrset if the path exists, else empty
  optionalFile = path: name:
    if pathExists path then
      { ${name} = { inherit path; type = "file"; }; }
    else
      {};

  optionalPath = path:
    if pathExists path then path else null;

  # Scan modules/<type>/ directories
  # Returns: { type = { name = path; ... }; ... }
  scanModuleTypes = path:
    if !pathExists path then
      {}
    else
      let
        entries = readDir path;
        typeNames = filter (n: entries.${n} == "directory") (attrNames entries);
      in
      listToAttrs (map (typeName: {
        name = typeName;
        value = scanDir (path + "/${typeName}");
      }) typeNames);

  # Scan templates/ directories
  # Returns: { name = { path, description }; ... }
  scanTemplates = path:
    if !pathExists path then
      {}
    else
      let
        entries = readDir path;
        dirNames = filter (n: entries.${n} == "directory") (attrNames entries);
      in
      listToAttrs (map (name: {
        inherit name;
        value = {
          path = path + "/${name}";
        };
      }) dirNames);

in
src: {
  packages =
    scanDir (src + "/packages")
    // optionalFile (src + "/package.nix") "default";

  devshells =
    scanDir (src + "/devshells")
    // optionalFile (src + "/devshell.nix") "default";

  checks = scanDir (src + "/checks");

  formatter = optionalPath (src + "/formatter.nix");

  lib = optionalPath (src + "/lib/default.nix");

  hosts = scanHosts (src + "/hosts");

  modules = scanModuleTypes (src + "/modules");

  templates = scanTemplates (src + "/templates");
}
