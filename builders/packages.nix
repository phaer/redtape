# builders/packages.nix — Build packages from discovered entries
#
# Returns: { packages = { <pname> = <drv>; ... }; }
{ callFile, filterPlatforms, withPrefix }:
{ discovered, scope, system }:
let
  inherit (builtins) attrNames concatMap listToAttrs map mapAttrs;

  built = mapAttrs (pname: entry:
    let path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
    in callFile scope path { inherit pname; }
  ) discovered;

  filtered = filterPlatforms system built;

  # Auto-checks: each package + its passthru.tests
  autoChecks =
    withPrefix "pkgs-" filtered
    // listToAttrs (concatMap (pname:
      let
        pkg   = filtered.${pname};
        tests = filterPlatforms system (pkg.passthru.tests or {});
      in map (tname: {
        name  = "pkgs-${pname}-${tname}";
        value = tests.${tname};
      }) (attrNames tests)
    ) (attrNames filtered));
in
{
  packages = filtered;
  inherit autoChecks;
}
