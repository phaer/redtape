# call-file.nix — callPackage-style file invocation
#
# Imports a .nix file and calls it with arguments matched from scope.
# Only passes arguments that the function explicitly accepts.

let
  inherit (builtins) intersectAttrs functionArgs;
in
scope: path: extraArgs:
  let
    fn = import path;
    args = functionArgs fn;
    allArgs = scope // extraArgs;
  in
  fn (intersectAttrs args allArgs)
