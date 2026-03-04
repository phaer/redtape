# red-tape — Convention-based Nix project builder on adios-flake
{ adios-flake }:
let
  inherit (builtins)
    attrNames
    foldl'
    isAttrs
    isList
    isFunction
    map
    ;

  adiosFlakeLib = adios-flake.lib or adios-flake;
  defaultModules = import ../modules;

  # Deep-merge two values: concatenate lists, recursively merge attrsets,
  # right side wins for scalars.
  deepMerge =
    a: b:
    if isList a && isList b then
      a ++ b
    else if isAttrs a && isAttrs b then
      foldl' (
        acc: key:
        acc
        // {
          ${key} = if acc ? ${key} then deepMerge acc.${key} b.${key} else b.${key};
        }
      ) a (attrNames b)
    else
      b;

  # Evaluate contrib-style modules (functions returning "/path" config attrsets),
  # strip leading "/" from keys, and deep-merge their results.
  evalContribModules =
    let
      stripLeadingSlash =
        s:
        let
          len = builtins.stringLength s;
        in
        if len > 0 && builtins.substring 0 1 s == "/" then builtins.substring 1 (len - 1) s else s;
      stripKeys =
        a:
        builtins.listToAttrs (
          map (k: {
            name = stripLeadingSlash k;
            value = a.${k};
          }) (attrNames a)
        );
    in
    foldl' (
      acc: mod:
      deepMerge acc (stripKeys (if isFunction mod then mod null else mod))
    ) { };

  mkFlake =
    {
      inputs,
      self ? null,
      src,
      prefix ? null,
      systems ? [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ],
      modules ? [ ],
      perSystem ? null,
      config ? { },
      flake ? { },
    }:
    let
      contribConfig = evalContribModules modules;
      baseConfig = {
        "red-tape/scan" = {
          inherit src self;
          inputs = inputs;
        }
        // (if prefix != null then { inherit prefix; } else { });
      };
    in
    adiosFlakeLib.mkFlake {
      inherit
        inputs
        self
        systems
        perSystem
        flake
        ;
      modules = [ defaultModules.redTape.default ];
      config = foldl' deepMerge baseConfig [
        contribConfig
        config
      ];
    };
in
{
  inherit mkFlake;
  modules = defaultModules;
}
