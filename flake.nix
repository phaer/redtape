{
  description = "red-tape — convention-based project builder on adios";

  # No flake inputs — reuse npins sources (same as adios itself)
  outputs = { ... }:
    let
      imported = import ./. {};
    in
    {
      # Make red-tape callable: inputs.red-tape { inherit inputs; }
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
