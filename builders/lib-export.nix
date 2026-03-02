# builders/lib-export.nix — Import and export lib/default.nix
#
# Returns: the lib attrset, or {} if libPath is null.
# If lib/default.nix is a function taking { flake, inputs },
# it's called with those args.  Otherwise the raw value is returned.
{ libPath, flake ? null, inputs ? {} }:
if libPath == null then {}
else
  let
    mod = import libPath;
  in
  if builtins.isFunction mod
  then mod { inherit flake inputs; }
  else mod
