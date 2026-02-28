# call-file.nix — callPackage-style file invocation
#
# Imports a .nix file and calls it with arguments matched from scope.
# Only passes arguments that the function explicitly accepts.
# Wraps with addErrorContext for clear error messages.

let
  inherit (builtins) addErrorContext intersectAttrs functionArgs;
in
scope: path: extraArgs:
  addErrorContext "while evaluating '${toString path}'" (
    let
      fn = import path;
      args = functionArgs fn;
      allArgs = scope // extraArgs;
    in
    fn (intersectAttrs args allArgs)
  )
