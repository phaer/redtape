# Edge case tests
let
  prelude = import ./prelude.nix;
  inherit (prelude) discover helpers fixtures;
  inherit (helpers) filterPlatforms;
in
{
  testFilterPlatformsKeepsMatching = {
    expr = filterPlatforms "x86_64-linux" {
      a = { meta.platforms = [ "x86_64-linux" "aarch64-linux" ]; };
      b = { meta.platforms = [ "aarch64-darwin" ]; };
      c = { meta = {}; };
    };
    expected = {
      a = { meta.platforms = [ "x86_64-linux" "aarch64-linux" ]; };
      c = { meta = {}; };
    };
  };

  testFilterPlatformsEmptyKeepsAll = {
    expr = builtins.attrNames (filterPlatforms "x86_64-linux" {
      a = { meta = {}; };
      b = { meta.platforms = []; };
    });
    expected = [ "a" "b" ];
  };

  testTemplateDescription = {
    expr =
      let
        found = discover.discoverAll (fixtures + "/full");
        templates = builtins.mapAttrs (name: entry:
          let f = entry.path + "/flake.nix";
          in { inherit (entry) path; description = if builtins.pathExists f then (import f).description or name else name; }
        ) found.templates;
      in templates.default.description;
    expected = "A default template";
  };

  testTemplateWithoutDescription = {
    expr =
      let
        found = discover.discoverAll (fixtures + "/full");
        templates = builtins.mapAttrs (name: entry:
          let f = entry.path + "/flake.nix";
          in { inherit (entry) path; description = if builtins.pathExists f then (import f).description or name else name; }
        ) found.templates;
      in templates.minimal.description;
    expected = "A minimal template";
  };
}
