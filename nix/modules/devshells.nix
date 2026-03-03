# red-tape/devshells — Build devshells from discovered expressions
#
# Inputs: ../scan (discovery), ../scope (per-system eval scope)
# Result: { devShells = { name = derivation; }; }
{ buildAll }:

{
  name = "devshells";
  inputs = {
    scan  = { path = "../scan"; };
    scope = { path = "../scope"; };
  };
  impl = { results, ... }:
    { devShells = buildAll results.scope.scope results.scan.discovered.devshells; };
}
