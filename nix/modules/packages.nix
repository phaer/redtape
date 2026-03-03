# red-tape/packages — Build packages from discovered expressions
#
# Inputs: ../scan (discovery), ../scope (per-system eval scope)
# Result: { packages = { name = derivation; }; }
{ buildAll, filterPlatforms }:

{
  name = "packages";
  inputs = {
    scan  = { path = "../scan"; };
    scope = { path = "../scope"; };
  };
  impl = { results, ... }:
    let
      s = results.scope;
      found = results.scan.discovered;
    in
    { packages = filterPlatforms s.system (buildAll s.scope found.packages); };
}
