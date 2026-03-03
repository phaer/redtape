# Shared builder helpers used by per-system modules
let
  inherit (builtins)
    addErrorContext
    attrNames
    elem
    filter
    functionArgs
    intersectAttrs
    listToAttrs
    map
    mapAttrs
    ;

  callFile =
    scope: path: extra:
    addErrorContext "while evaluating '${toString path}'" (
      let
        fn = import path;
      in
      fn (intersectAttrs (functionArgs fn) (scope // extra))
    );

  entryPath = e: if e.type == "directory" then e.path + "/default.nix" else e.path;

  buildAll = scope: mapAttrs (pname: e: callFile scope (entryPath e) { inherit pname; });

  filterPlatforms =
    system: a:
    listToAttrs (
      filter (x: x != null) (
        map (
          n:
          let
            p = a.${n}.meta.platforms or [ ];
          in
          if p == [ ] || elem system p then
            {
              name = n;
              value = a.${n};
            }
          else
            null
        ) (attrNames a)
      )
    );

  withPrefix =
    pre: a:
    listToAttrs (
      map (n: {
        name = "${pre}${n}";
        value = a.${n};
      }) (attrNames a)
    );
in
{
  inherit
    callFile
    entryPath
    buildAll
    filterPlatforms
    withPrefix
    ;
}
