# red-tape/lib — Import and expose the project's lib/default.nix
{
  name = "lib";
  inputs = {
    scan = {
      path = "../scan";
    };
  };
  impl =
    { results, ... }:
    let
      inherit (builtins) isFunction;
      inherit (results.scan) discovered self inputs;
      raw =
        if discovered.lib == null then
          { }
        else
          let
            m = import discovered.lib;
          in
          if isFunction m then
            m {
              flake = self;
              inherit inputs;
            }
          else
            m;
    in
    if raw != { } then { lib = raw; } else { };
}
