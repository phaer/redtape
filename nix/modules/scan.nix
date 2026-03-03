# red-tape/scan — Pure filesystem discovery + shared flake context
#
# Options:
#   src    — Source path to scan (typically `self`)
#   prefix — Optional subdirectory prefix
#   self   — The flake self (path-like, for threading as `flake` into user exprs)
#   inputs — All flake inputs
#
# Result: { discovered, src, self, allInputs }
#   discovered — the full discoverAll attrset
#   src        — resolved source path
#   self       — flake self (as-is)
#   allInputs  — inputs with self merged in
{ discover }:

let
  inherit (builtins) isPath removeAttrs;
in
{
  name = "scan";
  options = {
    src = {
      type = {
        name = "path-like";
        verify = v:
          if isPath v || (builtins.isAttrs v && v ? outPath) || builtins.isString v
          then null
          else "expected a path, string, or attrset with outPath";
      };
    };
    prefix = {
      type = {
        name = "nullable-string";
        verify = v:
          if v == null || builtins.isString v || isPath v
          then null
          else "expected null, a string, or a path";
      };
      default = null;
    };
    self = {
      # Never inspected — avoids forcing the flake fixpoint to WHNF.
      type = { name = "any"; verify = _: null; };
      default = null;
    };
    inputs = {
      type = { name = "attrs"; verify = v: if builtins.isAttrs v then null else "expected attrset"; };
      default = {};
    };
  };
  impl = { options, ... }:
    let
      src = options.src;
      prefix = options.prefix;
      self = options.self;
      resolvedSrc =
        if prefix != null then
          (if isPath prefix then prefix else src + "/${prefix}")
        else src;
      allInputs = (removeAttrs options.inputs [ "self" ])
        // (if self != null then { inherit self; } else {});
    in
    {
      discovered = discover.discoverAll resolvedSrc;
      inherit src self allInputs;
    };
}
