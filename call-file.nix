# call-file.nix — callPackage-style auto-injection for discovered .nix files
#
# Pure utility: takes a scope attrset and a path, imports the file,
# inspects its function arguments, and passes only what's requested.
let
  inherit (builtins)
    addErrorContext
    functionArgs
    intersectAttrs
    ;
in
{
  # Call a .nix file with auto-injected arguments from scope.
  # Extra args (e.g. { pname }) are merged into the scope before intersection.
  callFile = scope: path: extraArgs:
    addErrorContext "while evaluating '${toString path}'" (
      let
        fn = import path;
        args = functionArgs fn;
      in
      fn (intersectAttrs args (scope // extraArgs))
    );
}
