# red-tape/packages — Build packages from discovered expressions
let
  inherit (import ../lib/utils.nix) buildAll filterPlatforms;
in
{
  name = "packages";
  inputs = {
    scan = {
      path = "../scan";
    };
    scope = {
      path = "../scope";
    };
    formatter = {
      path = "../formatter";
    };
  };
  impl =
    { results, ... }:
    let
      s = results.scope;
      found = results.scan.discovered;
    in
    {
      packages = filterPlatforms s.system (
        buildAll s.scope found.packages // { formatter = results.formatter.formatter; }
      );
    };
}
