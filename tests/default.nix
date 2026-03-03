# All tests — import each test file and merge into one attrset
let
  prefix =
    pre: tests:
    builtins.listToAttrs (
      builtins.map (n: {
        name = "test_${pre}_${builtins.substring 4 (builtins.stringLength n) n}";
        value = tests.${n};
      }) (builtins.attrNames tests)
    );
in
prefix "scanDir" (import ./scan-dir.nix)
// prefix "discover" (import ./discover.nix)
// prefix "integration" (import ./integration.nix)
// prefix "hosts" (import ./hosts.nix)
// prefix "modules" (import ./modules-export.nix)
// prefix "templates" (import ./templates.nix)
// prefix "lib" (import ./lib-export.nix)
