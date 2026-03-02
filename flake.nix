{
  description = "red-tape — convention-based project builder on adios-flake";

  inputs = {
    adios-flake.url = "github:Mic92/adios-flake";
  };

  outputs = { adios-flake, ... }:
    let
      imported = import ./. { inherit adios-flake; };
    in
    {
      lib = imported // {
        __functor = _: args:
          imported.mkFlake (args // {
            systems = args.systems or [
              "x86_64-linux"
              "aarch64-linux"
              "aarch64-darwin"
              "x86_64-darwin"
            ];
          });
      };
    };
}
