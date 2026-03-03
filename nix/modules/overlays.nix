# red-tape/overlays — Discover and build overlay expressions
#
# Inputs: ../scan (discovery + flake context)
# Result: { overlays = { name = overlay-fn; }; }
{ buildAll }:

{
  name = "overlays";
  inputs = {
    scan = { path = "../scan"; };
  };
  impl = { results, ... }:
    let
      inherit (results.scan) discovered self allInputs;
      agnostic = { flake = self; inputs = allInputs; };
    in
    if discovered.overlays != {} then
      { overlays = buildAll agnostic discovered.overlays; }
    else
      {};
}
