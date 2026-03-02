# Tests for template export
let
  prelude = import ./prelude.nix;
  inherit (prelude) _internal fixtures;
  inherit (_internal) discover;
  inherit (_internal.builders) buildTemplates;
in
{
  testTemplateNames = {
    expr = builtins.sort builtins.lessThan
      (builtins.attrNames (buildTemplates (discover.discoverAll (fixtures + "/full")).templates));
    expected = [ "default" "minimal" ];
  };

  testTemplateDescription = {
    expr = (buildTemplates (discover.discoverAll (fixtures + "/full")).templates).default.description;
    expected = "A default template";
  };

  testEmptyTemplates = {
    expr = buildTemplates (discover.discoverAll (fixtures + "/empty")).templates;
    expected = {};
  };
}
