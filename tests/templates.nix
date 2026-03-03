# Template tests
let
  prelude = import ./prelude.nix;
  inherit (prelude) discover fixtures;

  mkTemplates = found: builtins.mapAttrs (name: entry:
    let f = entry.path + "/flake.nix";
    in { inherit (entry) path; description = if builtins.pathExists f then (import f).description or name else name; }
  ) found.templates;
in
{
  testTemplateNames = {
    expr = builtins.sort builtins.lessThan
      (builtins.attrNames (mkTemplates (discover.discoverAll (fixtures + "/full"))));
    expected = [ "default" "minimal" ];
  };

  testTemplateDescription = {
    expr = (mkTemplates (discover.discoverAll (fixtures + "/full"))).default.description;
    expected = "A default template";
  };

  testEmptyTemplates = {
    expr = mkTemplates (discover.discoverAll (fixtures + "/empty"));
    expected = {};
  };
}
