# Integration tests — builders with mock pkgs
let
  prelude = import ./prelude.nix;
  inherit (prelude)
    mockPkgs
    sys
    fixtures
    discover
    helpers
    ;
  inherit (helpers) callFile buildAll filterPlatforms;

  sort = builtins.sort builtins.lessThan;
  names = builtins.attrNames;

  evalFixture =
    src:
    let
      found = discover.discoverAll src;
      scope = {
        pkgs = mockPkgs;
        system = sys;
        lib = mockPkgs.lib;
      };
      packages = filterPlatforms sys (buildAll scope found.packages);
    in
    {
      inherit packages;
    };

  full = evalFixture (fixtures + "/full");
  minimal = evalFixture (fixtures + "/minimal");
in
{
  # --- Packages ---

  testFullPackageNames = {
    expr = sort (names full.packages);
    expected = [
      "goodbye"
      "hello"
    ];
  };

  testPackageType = {
    expr = full.packages.hello.type;
    expected = "derivation";
  };

  testMinimalPackage = {
    expr = names minimal.packages;
    expected = [ "default" ];
  };

  testPlatformFilterKeeps = {
    expr =
      let
        scope = {
          pkgs = mockPkgs;
          system = sys;
          lib = mockPkgs.lib;
        };
        pkg = {
          type = "derivation";
          name = "kept";
          meta.platforms = [ "x86_64-linux" ];
        };
      in
      names (filterPlatforms sys { kept = pkg; });
    expected = [ "kept" ];
  };

  testPlatformFilterDrops = {
    expr =
      let
        pkg = {
          type = "derivation";
          name = "dropped";
          meta.platforms = [ "aarch64-darwin" ];
        };
      in
      names (filterPlatforms sys { dropped = pkg; });
    expected = [ ];
  };
}
