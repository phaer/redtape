# red-tape/checks — Build checks + auto-checks from packages/devshells/hosts
#
# Inputs: ../scan, ../scope, ../packages, ../devshells, ../hosts
# Result: { checks = { name = derivation; }; }
{ buildAll, filterPlatforms, withPrefix }:

{
  name = "checks";
  inputs = {
    scan      = { path = "../scan"; };
    scope     = { path = "../scope"; };
    packages  = { path = "../packages"; };
    devshells = { path = "../devshells"; };
    hosts     = { path = "../hosts"; };
  };
  impl = { results, ... }:
    let
      inherit (builtins) attrNames concatMap listToAttrs map;
      s = results.scope;
      system = s.system;
      found = results.scan.discovered;
      packages = results.packages.packages;
      devShells = results.devshells.devShells;
      hostResult = results.hosts;

      # User-written checks
      userChecks = filterPlatforms system (buildAll s.scope found.checks);

      # Auto-checks: packages as checks + passthru.tests
      pkgChecks = withPrefix "pkgs-" packages
        // listToAttrs (concatMap (pname:
          let tests = filterPlatforms system (packages.${pname}.passthru.tests or {});
          in map (t: { name = "pkgs-${pname}-${t}"; value = tests.${t}; }) (attrNames tests)
        ) (attrNames packages));

      # Auto-checks: devshells as checks
      devshellChecks = withPrefix "devshell-" devShells;

      # Auto-checks: host toplevel builds for this system
      hostAutoChecks =
        let ac = hostResult.autoChecks or null;
        in if ac != null then ac system else {};
    in
    { checks = hostAutoChecks // pkgChecks // devshellChecks // userChecks; };
}
