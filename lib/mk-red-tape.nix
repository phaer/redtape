# mk-red-tape.nix — Core entry point logic shared by flake and traditional modes
#
# Only includes adios modules for outputs that exist in the source tree.
# If there are no packages/, no devshells/, etc., those modules are not
# in the tree at all — zero overhead.

{ adios }:

let
  inherit (builtins)
    attrNames
    concatMap
    filter
    head
    tail
    listToAttrs
    map
    mapAttrs
    ;

  transpose = import ./transpose.nix;
  filterPlatforms = import ./filter-platforms.nix;
  discover = import ../modules/discover.nix;
  buildTemplates = import ./build-templates.nix;

  callMod = path: import path adios;

  mkConfigOptions = config:
    listToAttrs (map (key: {
      name = "/${key}";
      value = config.${key};
    }) (attrNames config));

  withPrefix = prefix: attrs:
    listToAttrs (map (name: {
      name = "${prefix}${name}";
      value = attrs.${name};
    }) (attrNames attrs));

  mkAllInputs = flakeInputs: self:
    flakeInputs // (if self != null then { self = self; } else {});

  # Only include adios modules for outputs that have discovered content.
  # /nixpkgs and /formatter are always present (formatter has a fallback).
  mkModules = { discovered, extraModules ? {} }:
    { nixpkgs   = callMod ../modules/nixpkgs.nix;
      formatter = callMod ../modules/formatter.nix;
    }
    // (if discovered.packages != {} then { packages  = callMod ../modules/packages.nix; } else {})
    // (if discovered.devshells != {} then { devshells = callMod ../modules/devshells.nix; } else {})
    // (if discovered.checks != {} then { checks = callMod ../modules/checks.nix; } else {})
    // (if discovered.hosts != {} then { hosts = callMod ../modules/hosts.nix; } else {})
    // (if discovered.overlays != {} then { overlays = callMod ../modules/overlays.nix; } else {})
    // (if discovered.modules != {} then { modules-export = callMod ../modules/modules-export.nix; } else {})
    // extraModules;

  mkExtraScope = { flakeInputs ? {}, self ? null, perSystem ? {} }:
    let allInputs = mkAllInputs flakeInputs self;
    in { inherit perSystem; }
    // (if self != null then { flake = self; } else {})
    // (if allInputs != {} then { inputs = allInputs; } else {});

  # Build adios options — only emits entries for modules in the tree.
  mkOptions =
    { modules, discovered, configOptions
    , extraScope ? {}, agnosticScope ? {}
    , flakeInputs ? {}, self ? null
    }: nixpkgsOpt:
    { "/nixpkgs" = nixpkgsOpt;
      "/formatter" = { formatterPath = discovered.formatter; inherit extraScope; };
    }
    // (if modules ? packages then {
      "/packages" = { discovered = discovered.packages; inherit extraScope; };
    } else {})
    // (if modules ? devshells then {
      "/devshells" = { discovered = discovered.devshells; inherit extraScope; };
    } else {})
    // (if modules ? checks then {
      "/checks" = { discovered = discovered.checks; inherit extraScope; };
    } else {})
    // (if modules ? hosts then {
      "/hosts" = { discovered = discovered.hosts; inherit flakeInputs self; };
    } else {})
    // (if modules ? overlays then {
      "/overlays" = { discovered = discovered.overlays; extraScope = agnosticScope; };
    } else {})
    // (if modules ? modules-export then {
      "/modules-export" = { discovered = discovered.modules; inherit flakeInputs self; };
    } else {})
    // configOptions;

  # Collect per-system results from the evaluated tree.
  collectPerSystem = { evaled, system }:
    let
      mods = evaled.modules;
      has = name: mods ? ${name};

      pkgResult = if has "packages"  then mods.packages {}  else { filteredPackages = {}; };
      devResult = if has "devshells" then mods.devshells {}  else { devShells = {}; };
      fmtResult = mods.formatter {};
      chkResult = if has "checks"    then mods.checks {}     else { checks = {}; };

      packageChecks =
        withPrefix "pkgs-" pkgResult.filteredPackages
        // listToAttrs (concatMap (pname:
          let
            pkg = pkgResult.filteredPackages.${pname};
            tests = filterPlatforms system (pkg.passthru.tests or {});
          in
          map (tname: {
            name = "pkgs-${pname}-${tname}";
            value = tests.${tname};
          }) (attrNames tests)
        ) (attrNames pkgResult.filteredPackages));

      devshellChecks = withPrefix "devshell-" devResult.devShells;
    in
    { packages = pkgResult.filteredPackages;
      devShells = devResult.devShells;
      formatter = fmtResult.formatter;
      checks = packageChecks // devshellChecks // chkResult.checks;
    };

  # Collect system-agnostic results (evaluated once, not transposed).
  collectAgnostic = evaled:
    let
      mods = evaled.modules;
      has = name: mods ? ${name};
      hostResult = if has "hosts" then mods.hosts {} else {};
      ovlResult = if has "overlays" then mods.overlays {} else {};
      modExpResult = if has "modules-export" then mods.modules-export {} else {};
    in
    hostResult
    // (if ovlResult != {} then { overlays = ovlResult.overlays; } else {})
    // modExpResult;

  # Import lib, handling both function and plain attrset forms
  importLib = { libPath, flake ? null, inputs ? {} }:
    if libPath == null then {}
    else
      let mod = import libPath;
      in if builtins.isFunction mod then mod { inherit flake inputs; }
         else mod;

  # ── Flake entry point ──────────────────────────────────────────────

  mkFlake =
    {
      inputs,
      self ? inputs.self or null,
      src ? (if self != null then self else throw "red-tape: either `self` or `src` must be provided"),
      prefix ? null,
      systems ? [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ],
      nixpkgs ? {},
      extraModules ? {},
      config ? {},
    }:
    let
      flakeInputs = builtins.removeAttrs inputs [ "self" ];
      allInputs = mkAllInputs flakeInputs self;

      resolvedSrc =
        if prefix != null then
          if builtins.isPath prefix then prefix
          else if builtins.isString prefix then src + "/${prefix}"
          else throw "red-tape: prefix must be a string or path"
        else
          src;

      discovered = discover resolvedSrc;
      configOptions = mkConfigOptions config;

      modules = mkModules { inherit discovered extraModules; };
      loaded = adios { name = "red-tape"; inherit modules; };

      nixpkgsFor = system:
        let
          cfg = nixpkgs.config or {};
          overlays = nixpkgs.overlays or [];
        in
        if cfg == {} && overlays == [] then
          inputs.nixpkgs.legacyPackages.${system}
        else
          import inputs.nixpkgs {
            inherit system;
            config = cfg;
            inherit overlays;
          };

      agnosticScope = mkExtraScope { inherit flakeInputs self; };

      mkOpts = system:
        let
          perSystem = mkPerSystem flakeInputs self system;
          extraScope = mkExtraScope { inherit flakeInputs self perSystem; };
        in
        mkOptions {
          inherit modules discovered configOptions extraScope agnosticScope flakeInputs self;
        } {
          inherit system;
          pkgs = nixpkgsFor system;
        };

      firstSystem = head systems;
      firstEvaled = loaded { options = mkOpts firstSystem; };
      firstResult = collectPerSystem { evaled = firstEvaled; system = firstSystem; };

      otherResults = listToAttrs (map (sys:
        let overridden = firstEvaled.override { options = mkOpts sys; };
        in { name = sys; value = collectPerSystem { evaled = overridden; system = sys; }; }
      ) (tail systems));

      allPerSystem = { ${firstSystem} = firstResult; } // otherResults;
      transposed = transpose allPerSystem;

      # System-agnostic: from adios modules (memoized, evaluated once)
      agnosticFromModules = collectAgnostic firstEvaled;

      # System-agnostic: from plain functions (templates, lib)
      templatesOutput = buildTemplates discovered.templates;
      libOutput = importLib { libPath = discovered.lib; flake = self; inputs = allInputs; };

      agnosticOutputs =
        agnosticFromModules
        // (if templatesOutput != {} then { templates = templatesOutput; } else {})
        // (if libOutput != {} then { lib = libOutput; } else {});

    in
    transposed // agnosticOutputs;

  # ── Helpers ─────────────────────────────────────────────────────────

  mkPerSystem = flakeInputs: self: system:
    let
      base = mapAttrs (_name: input:
        if builtins.isAttrs input then
          (input.legacyPackages.${system} or {})
          // (input.packages.${system} or {})
        else
          input
      ) flakeInputs;
    in
    if self != null then
      base // {
        self = (self.legacyPackages.${system} or {}) // (self.packages.${system} or {});
      }
    else
      base;

  # ── Traditional entry point ─────────────────────────────────────────

  eval =
    {
      pkgs,
      src,
      extraModules ? {},
      config ? {},
      extraScope ? {},
    }:
    let
      system = pkgs.system or pkgs.stdenv.hostPlatform.system;
      discovered = discover src;
      configOptions = mkConfigOptions config;

      modules = mkModules { inherit discovered extraModules; };
      loaded = adios { name = "red-tape"; inherit modules; };

      opts = mkOptions {
        inherit modules discovered configOptions extraScope;
      } { inherit system pkgs; };

      evaled = loaded { options = opts; };
      result = collectPerSystem { inherit evaled system; };
      agnostic = collectAgnostic evaled;

      templatesOutput = buildTemplates discovered.templates;
      libOutput = importLib { libPath = discovered.lib; };
    in
    result // agnostic // {
      shell = result.devShells.default or null;
    }
    // (if templatesOutput != {} then { templates = templatesOutput; } else {})
    // (if libOutput != {} then { lib = libOutput; } else {});

in
{
  inherit mkFlake eval;
}
