# red-tape/templates — Discover template directories
#
# Inputs: ../scan
# Result: { templates = { name = { path; description; }; }; }
{
  name = "templates";
  inputs = {
    scan = { path = "../scan"; };
  };
  impl = { results, ... }:
    let
      inherit (builtins) mapAttrs pathExists;
      found = results.scan.discovered;
      templates = mapAttrs (name: e: {
        inherit (e) path;
        description =
          let f = e.path + "/flake.nix";
          in if pathExists f then (import f).description or name else name;
      }) found.templates;
    in
    if found.templates != {} then { inherit templates; }
    else {};
}
