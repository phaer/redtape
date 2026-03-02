# red-tape — Convention-based Nix project builder on adios
#
# Flake:       outputs = { ... }: (import ./.).mkFlake { inherit inputs; };
# Traditional: (import ./.).eval { inherit pkgs; src = ./.; }
{
  __sources ? import ./npins,
  adios ? (import __sources.adios).adios,
}:
let
  inherit (builtins)
    addErrorContext
    all
    attrNames
    attrValues
    concatMap
    elem
    filter
    foldl'
    functionArgs
    head
    intersectAttrs
    isAttrs
    isFunction
    isPath
    isString
    listToAttrs
    map
    mapAttrs
    match
    pathExists
    readDir
    tail
    ;

  types = adios.types;

  # ── Utilities ───────────────────────────────────────────────────────

  callFile = scope: path: extraArgs:
    addErrorContext "while evaluating '${toString path}'" (
      let
        fn = import path;
        args = functionArgs fn;
      in
      fn (intersectAttrs args (scope // extraArgs))
    );

  filterPlatforms = system: packages:
    listToAttrs (filter (x: x != null) (map (name:
      let
        pkg = packages.${name};
        platforms = pkg.meta.platforms or [];
      in
      if platforms == [] || elem system platforms
      then { inherit name; value = pkg; }
      else null
    ) (attrNames packages)));

  withPrefix = prefix: attrs:
    listToAttrs (map (name: {
      name = "${prefix}${name}";
      value = attrs.${name};
    }) (attrNames attrs));

  mkAllInputs = flakeInputs: self:
    flakeInputs // (if self != null then { inherit self; } else {});

  # ── Directory scanning ──────────────────────────────────────────────

  matchNixFile = match "(.+)\\.nix$";

  scanDir = path:
    if !pathExists path then {}
    else
      let
        entries = readDir path;
        names = attrNames entries;
        nixFiles = listToAttrs (filter (x: x != null) (map (name:
          let m = matchNixFile name;
          in if entries.${name} == "regular" && m != null && name != "default.nix"
          then { name = head m; value = { path = path + "/${name}"; type = "file"; }; }
          else null
        ) names));
        dirs = listToAttrs (filter (x: x != null) (map (name:
          if entries.${name} == "directory" && pathExists (path + "/${name}/default.nix")
          then { inherit name; value = { path = path + "/${name}"; type = "directory"; }; }
          else null
        ) names));
      in
      dirs // nixFiles;  # .nix files take precedence

  # Scan hosts/ subdirectories for files matching a list of { type; file }.
  # Checked in order — first match wins per host directory.
  # Callers decide which types to look for; nothing is hardcoded here.
  scanHosts = path: hostTypes:
    let
      detectType = hostPath:
        let matches = filter (t: pathExists (hostPath + "/${t.file}")) hostTypes;
        in if matches == [] then null
           else let t = head matches;
                in { type = t.type; configPath = hostPath + "/${t.file}"; };
    in
    if !pathExists path then {}
    else
      let entries = readDir path;
      in listToAttrs (filter (x: x != null) (map (name:
        if entries.${name} != "directory" then null
        else let hostPath = path + "/${name}"; config = detectType hostPath;
        in if config != null
          then { inherit name; value = config // { inherit hostPath; }; }
          else null
      ) (attrNames entries)));

  scanModuleTypes = path:
    if !pathExists path then {}
    else
      let entries = readDir path;
      in listToAttrs (map (typeName: {
        name = typeName;
        value = scanDir (path + "/${typeName}");
      }) (filter (n: entries.${n} == "directory") (attrNames entries)));

  scanTemplates = path:
    if !pathExists path then {}
    else
      let entries = readDir path;
      in listToAttrs (map (name: {
        inherit name;
        value = { path = path + "/${name}"; };
      }) (filter (n: entries.${n} == "directory") (attrNames entries)));

  optionalFile = path: name:
    if pathExists path then { ${name} = { inherit path; type = "file"; }; } else {};

  optionalPath = path:
    if pathExists path then path else null;

  # Templates and lib aren't adios modules — discovered separately by entry points.
  discoverTemplates = src: scanTemplates (src + "/templates");
  discoverLib       = src: optionalPath (src + "/lib/default.nix");

  # Convenience: full discovery including templates, lib, and formatter path.
  # Combines runDiscover (module descriptors) with the non-module outputs.
  discover = src: descriptors:
    let mods = runDiscover src descriptors;
    in mods // {
      formatter = optionalPath (src + "/formatter.nix");
      templates = discoverTemplates src;
      lib       = discoverLib src;
    };

  # ── Transpose ──────────────────────────────────────────────────────

  transpose = perSystemResults:
    let
      systems = attrNames perSystemResults;
      allCategories = foldl' (acc: sys:
        let cats = attrNames perSystemResults.${sys};
        in acc ++ (filter (c: !elem c acc) cats)
      ) [] systems;
    in
    listToAttrs (map (cat: {
      name = cat;
      value = listToAttrs (map (sys: {
        name = sys;
        value = perSystemResults.${sys}.${cat} or {};
      }) systems);
    }) allCategories);

  # ── Templates ──────────────────────────────────────────────────────

  buildTemplates = mapAttrs (name: entry:
    let flakeNix = entry.path + "/flake.nix";
    in {
      inherit (entry) path;
      description =
        if pathExists flakeNix then (import flakeNix).description or name
        else name;
    });

  # ── Lib export ─────────────────────────────────────────────────────

  importLib = { libPath, flake ? null, inputs ? {} }:
    if libPath == null then {}
    else let mod = import libPath;
    in if isFunction mod then mod { inherit flake inputs; } else mod;

  # ── Adios module definitions ────────────────────────────────────────

  # Data-only: provides system + pkgs to downstream modules
  modNixpkgs = {
    name = "nixpkgs";
    perSystem = true;  # infrastructure module — not collected as an output
    options = {
      system = { type = types.string; };
      pkgs   = { type = types.attrs; };
    };
  };

  # ── Module descriptors ─────────────────────────────────────────────
  #
  # Each descriptor is an adios module attrset augmented with red-tape metadata:
  #
  #   discover  : src -> value | null   — how to find this module's inputs on disk
  #                                        null or {} means "nothing found, skip"
  #   optionsFn : ctx -> options-attrset — how to turn discovered value + context
  #                                        into adios options for this module
  #   perSystem : bool (default false)  — true: depends on /nixpkgs, result is
  #                                        transposed across systems; false: agnostic
  #
  # The discover/optionsFn/perSystem fields are ignored by adios (extra keys are
  # dropped by loadModule). They are red-tape's extension protocol.

  # Generic per-system module factory (packages / devshells / checks)
  mkPerSystemMod = { name, discover, postProcess ? ({ built, ... }: built) }: {
    inherit name discover;
    perSystem = true;
    optionsFn = { discovered, extraScope, ... }:
      { discovered = discovered.${name}; inherit extraScope; };
    inputs.nixpkgs = { path = "/nixpkgs"; };
    options = {
      discovered = { type = types.attrs; default = {}; };
      extraScope = { type = types.attrs; default = {}; };
    };
    impl = { inputs, options, ... }:
      let
        system = inputs.nixpkgs.system;
        pkgs   = inputs.nixpkgs.pkgs;
        scope  = { inherit pkgs system; lib = pkgs.lib; } // options.extraScope;
        built  = mapAttrs (pname: entry:
          let path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
          in callFile scope path { inherit pname; }
        ) options.discovered;
      in
      postProcess { inherit system pkgs built; };
  };

  modPackages = mkPerSystemMod {
    name    = "packages";
    discover = src:
      let v = scanDir (src + "/packages") // optionalFile (src + "/package.nix") "default";
      in if v == {} then null else v;
    postProcess = { system, built, ... }:
      { packages = built; filteredPackages = filterPlatforms system built; };
  };

  modDevshells = mkPerSystemMod {
    name    = "devshells";
    discover = src:
      let v = scanDir (src + "/devshells") // optionalFile (src + "/devshell.nix") "default";
      in if v == {} then null else v;
    postProcess = { built, ... }: { devShells = built; };
  };

  modChecks = mkPerSystemMod {
    name    = "checks";
    discover = src:
      let v = scanDir (src + "/checks");
      in if v == {} then null else v;
    postProcess = { system, built, ... }: { checks = filterPlatforms system built; };
  };

  modFormatter = {
    name      = "formatter";
    perSystem = true;
    # formatter is always present (falls back to nixfmt-tree) — no discover needed
    optionsFn = { discovered, extraScope, ... }:
      { formatterPath = discovered.formatter or null; inherit extraScope; };
    inputs.nixpkgs = { path = "/nixpkgs"; };
    options = {
      formatterPath = { type = types.any;   default = null; };
      extraScope    = { type = types.attrs; default = {}; };
    };
    impl = { inputs, options, ... }:
      let
        pkgs  = inputs.nixpkgs.pkgs;
        scope = { inherit pkgs; system = inputs.nixpkgs.system; lib = pkgs.lib; }
          // options.extraScope;
      in {
        formatter =
          if options.formatterPath != null then callFile scope options.formatterPath {}
          else pkgs.nixfmt-tree or pkgs.nixfmt
            or (throw "red-tape: no formatter.nix and nixfmt-tree unavailable");
      };
  };

  modOverlays = {
    name     = "overlays";
    discover = src:
      let v = scanDir (src + "/overlays") // optionalFile (src + "/overlay.nix") "default";
      in if v == {} then null else v;
    optionsFn = { discovered, agnosticScope, ... }:
      { discovered = discovered.overlays; extraScope = agnosticScope; };
    options = {
      discovered = { type = types.attrs; default = {}; };
      extraScope = { type = types.attrs; default = {}; };
    };
    impl = { options, ... }: {
      overlays = mapAttrs (pname: entry:
        let path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
        in callFile options.extraScope path { inherit pname; }
      ) options.discovered;
    };
  };

  coreHostTypes = [
    { type = "custom"; file = "default.nix"; }
    { type = "nixos";  file = "configuration.nix"; }
    { type = "darwin"; file = "darwin-configuration.nix"; }
  ];

  modHosts = {
    name     = "hosts";
    discover = src: scanHosts (src + "/hosts") coreHostTypes;
    optionsFn = { discovered, flakeInputs, self, ... }:
      { discovered = discovered.hosts; inherit flakeInputs self; };
    autoChecks = { result, system }:
      let
        mkHostChecks = prefix: hosts:
          listToAttrs (filter (x: x != null) (map (name:
            let
              host = hosts.${name};
              hostSystem = host.config.nixpkgs.hostPlatform.system or null;
            in
            if hostSystem == system
            then { name = "${prefix}-${name}"; value = host.config.system.build.toplevel; }
            else null
          ) (attrNames hosts)));
      in
      mkHostChecks "nixos" (result.nixosConfigurations or {})
      // mkHostChecks "darwin" (result.darwinConfigurations or {});
    options = {
      discovered  = { type = types.attrs; default = {}; };
      flakeInputs = { type = types.attrs; default = {}; };
      self        = { type = types.any;   default = null; };
    };
    impl = { options, ... }:
      let
        inherit (options) flakeInputs self;
        allInputs   = flakeInputs // (if self != null then { inherit self; } else {});
        specialArgs = { flake = self; inputs = allInputs; };
        classMap    = { "nixos" = "nixosConfigurations"; "nix-darwin" = "darwinConfigurations"; };

        loadHost = hostName: hostInfo:
          addErrorContext "while building host '${hostName}' (${hostInfo.type})" (
            if hostInfo.type == "custom" then
              import hostInfo.configPath {
                inherit (specialArgs) flake inputs;
                inherit hostName;
              }
            else if hostInfo.type == "nixos" then {
              class = "nixos";
              value = flakeInputs.nixpkgs.lib.nixosSystem {
                modules     = [ hostInfo.configPath ];
                specialArgs = specialArgs // { inherit hostName; };
              };
            }
            else if hostInfo.type == "darwin" then
              let nix-darwin = flakeInputs.nix-darwin
                or (throw "red-tape: host '${hostName}' needs inputs.nix-darwin");
              in {
                class = "nix-darwin";
                value = nix-darwin.lib.darwinSystem {
                  modules     = [ hostInfo.configPath ];
                  specialArgs = specialArgs // { inherit hostName; };
                };
              }
            else throw "red-tape: unknown host type '${hostInfo.type}' for '${hostName}'"
          );

        loaded = mapAttrs loadHost options.discovered;
        mkCategory = category:
          listToAttrs (filter (x: x != null) (map (name:
            let host = loaded.${name};
            in if (classMap.${host.class} or null) == category
              then { inherit name; value = host.value; }
              else null
          ) (attrNames loaded)));
      in {
        nixosConfigurations  = mkCategory "nixosConfigurations";
        darwinConfigurations = mkCategory "darwinConfigurations";
      };
  };

  typeAliases = { nixos = "nixosModules"; darwin = "darwinModules"; home = "homeModules"; };

  modModulesExport = {
    name     = "modules-export";
    discover = src:
      let v = scanModuleTypes (src + "/modules");
      in if v == {} then null else v;
    optionsFn = { discovered, flakeInputs, self, ... }:
      { discovered = discovered.modules-export; inherit flakeInputs self; };
    options = {
      discovered  = { type = types.attrs; default = {}; };
      flakeInputs = { type = types.attrs; default = {}; };
      self        = { type = types.any;   default = null; };
    };
    impl = { options, ... }:
      let
        inherit (options) flakeInputs self;
        allInputs     = flakeInputs // (if self != null then { inherit self; } else {});
        publisherArgs = { flake = self; inputs = allInputs; };

        expectsPublisherArgs = fn:
          let args = functionArgs fn;
          in isFunction fn && args != {}
          && all (arg: elem arg (attrNames publisherArgs)) (attrNames args);

        importModule = entry:
          let
            path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
            mod  = import path;
          in
          if expectsPublisherArgs mod
          then mod (intersectAttrs (functionArgs mod) publisherArgs)
          else path;

        allModules = mapAttrs (_: entries: mapAttrs (_: importModule) entries) options.discovered;
      in
      foldl' (acc: typeName:
        let alias = typeAliases.${typeName} or null;
        in if alias != null && options.discovered ? ${typeName}
          then acc // { ${alias} = allModules.${typeName}; }
          else acc
      ) {} (attrNames options.discovered);
  };

  # ── Module tree assembly ────────────────────────────────────────────
  #
  # coreDescriptors: the built-in module descriptors, keyed by name.
  # extraModules: user-supplied descriptors (same shape) keyed by name — can
  #   override a core descriptor (same key) or add entirely new ones.
  #
  # Both discover and optionsFn are honoured for all descriptors generically.

  coreDescriptors = {
    nixpkgs        = modNixpkgs;
    formatter      = modFormatter;
    packages       = modPackages;
    devshells      = modDevshells;
    checks         = modChecks;
    overlays       = modOverlays;
    hosts          = modHosts;
    modules-export = modModulesExport;
  };

  # Run all descriptors' discover functions and collect non-null/non-empty results.
  # The key in the returned attrset matches the descriptor's name.
  # A discover function returns null or {} to signal "nothing found".
  isEmpty = v: v == null || v == {};
  runDiscover = src: descriptors:
    foldl' (acc: desc:
      if desc ? discover
      then let v = desc.discover src;
           in if !isEmpty v then acc // { ${desc.name} = v; } else acc
      else acc
    ) {} (attrValues descriptors);

  # Build the adios module tree from all descriptors.
  # A descriptor is included if:
  #   - it has no discover (always present, e.g. nixpkgs, formatter), or
  #   - its name appears in discovered (discover returned non-null)
  mkModules = descriptors: discovered:
    listToAttrs (filter (x: x != null) (map (name:
      let desc = descriptors.${name};
      in if !(desc ? discover) || discovered ? ${name}
         then { inherit name; value = desc; }
         else null
    ) (attrNames descriptors)));

  mkExtraScope = { flakeInputs ? {}, self ? null, perSystem ? {} }:
    let allInputs = mkAllInputs flakeInputs self;
    in { inherit perSystem; }
    // (if self != null then { flake = self; } else {})
    // (if allInputs != {} then { inputs = allInputs; } else {});

  mkConfigOptions = config:
    listToAttrs (map (key: { name = "/${key}"; value = config.${key}; }) (attrNames config));

  # Build the adios options attrset from all active descriptors.
  # For each descriptor with optionsFn, call it with context to get its options.
  # configOptions (from user's `config` param) are merged last and win.
  # Build adios options from active descriptors (those present in modules).
  # Each descriptor's optionsFn is called with context to produce its options.
  # configOptions (from user's `config` param) are merged last and win.
  mkOptions =
    { descriptors, discovered, configOptions
    , extraScope ? {}, agnosticScope ? {}
    , flakeInputs ? {}, self ? null
    }: nixpkgsOpt:
    let
      ctx = { inherit discovered extraScope agnosticScope flakeInputs self; };
      # Include a descriptor's options if it has optionsFn AND is active
      # (either has no discover field, or was discovered).
      isActive = desc: !(desc ? discover) || discovered ? ${desc.name};
      optFromDescriptors = foldl' (acc: desc:
        if desc ? optionsFn && isActive desc
        then acc // { "/${desc.name}" = desc.optionsFn ctx; }
        else acc
      ) {} (attrValues descriptors);
    in
    { "/nixpkgs" = nixpkgsOpt; }
    // optFromDescriptors
    // configOptions;

  # ── Result collection ──────────────────────────────────────────────

  collectPerSystem = { descriptors, evaled, system, agnosticResults ? {} }:
    let
      mods = evaled.modules;
      has  = name: mods ? ${name};

      # Core cross-referencing logic: packages and devshells feed into checks
      pkgResult = if has "packages"  then mods.packages {}  else { filteredPackages = {}; };
      devResult = if has "devshells" then mods.devshells {}  else { devShells = {}; };
      fmtResult = mods.formatter {};
      chkResult = if has "checks"    then mods.checks {}     else { checks = {}; };

      packageChecks =
        withPrefix "pkgs-" pkgResult.filteredPackages
        // listToAttrs (concatMap (pname:
          let
            pkg   = pkgResult.filteredPackages.${pname};
            tests = filterPlatforms system (pkg.passthru.tests or {});
          in map (tname: {
            name  = "pkgs-${pname}-${tname}";
            value = tests.${tname};
          }) (attrNames tests)
        ) (attrNames pkgResult.filteredPackages));

      # Auto-checks from any descriptor that declares autoChecks.
      # Each descriptor's autoChecks receives its impl result and the current
      # system, returning { name = drv; }.
      # For agnostic descriptors, use pre-computed agnosticResults to avoid
      # re-forcing host evaluation per system.
      descriptorAutoChecks =
        foldl' (acc: desc:
          if desc ? autoChecks && has desc.name
          then let result =
                 if !(desc.perSystem or false) && agnosticResults ? ${desc.name}
                 then agnosticResults.${desc.name}
                 else mods.${desc.name} {};
               in acc // desc.autoChecks { inherit result system; }
          else acc
        ) {} (attrValues descriptors);

      coreResult = {
        packages  = pkgResult.filteredPackages;
        devShells = devResult.devShells;
        formatter = fmtResult.formatter;
        checks    = packageChecks // withPrefix "devshell-" devResult.devShells
                    // descriptorAutoChecks // chkResult.checks;
      };

      # Extra per-system descriptors (not in core): just merge their results
      coreNames = [ "nixpkgs" "packages" "devshells" "formatter" "checks" ];
      extraPerSystem = foldl' (acc: desc:
        if (desc.perSystem or false) && !(elem desc.name coreNames) && has desc.name
        then acc // (mods.${desc.name} {})
        else acc
      ) {} (attrValues descriptors);
    in
    coreResult // extraPerSystem;

  # Returns { <desc-name> = impl-result; ... } for all agnostic descriptors.
  # Each result is computed once and shared.
  collectAgnosticByName = { descriptors, evaled }:
    let
      mods = evaled.modules;
      has  = name: mods ? ${name};
      agnosticDescs = filter (desc: !(desc.perSystem or false)) (attrValues descriptors);
    in
    listToAttrs (filter (x: x != null) (map (desc:
      if has desc.name
      then { name = desc.name; value = mods.${desc.name} {}; }
      else null
    ) agnosticDescs));

  # Merges all agnostic descriptor results into a single attrset (flake outputs).
  collectAgnostic = args:
    let byName = collectAgnosticByName args;
    in foldl' (acc: result: acc // result) {} (attrValues byName);

  # ── perSystem helper ───────────────────────────────────────────────

  mkPerSystem = flakeInputs: self: system:
    let
      base = mapAttrs (_: input:
        if isAttrs input
        then (input.legacyPackages.${system} or {}) // (input.packages.${system} or {})
        else input
      ) flakeInputs;
    in
    if self != null then
      base // { self = (self.legacyPackages.${system} or {}) // (self.packages.${system} or {}); }
    else base;

  # ── Flake entry point ──────────────────────────────────────────────

  mkFlake =
    { inputs
    , self ? inputs.self or null
    , src ? (if self != null then self else throw "red-tape: either self or src required")
    , prefix ? null
    , systems ? [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ]
    , nixpkgs ? {}
    , extraModules ? {}
    , config ? {}
    }:
    let
      flakeInputs = builtins.removeAttrs inputs [ "self" ];
      allInputs = mkAllInputs flakeInputs self;

      resolvedSrc =
        if prefix != null then
          if isPath prefix then prefix
          else if isString prefix then src + "/${prefix}"
          else throw "red-tape: prefix must be a string or path"
        else src;
      descriptors   = coreDescriptors // extraModules;
      discovered    = runDiscover resolvedSrc descriptors;
      configOptions = mkConfigOptions config;
      modules       = mkModules descriptors discovered;
      loaded        = adios { name = "red-tape"; inherit modules; };

      nixpkgsFor = system:
        let cfg = nixpkgs.config or {}; overlays = nixpkgs.overlays or [];
        in if cfg == {} && overlays == []
          then inputs.nixpkgs.legacyPackages.${system}
          else import inputs.nixpkgs { inherit system; config = cfg; inherit overlays; };

      agnosticScope = mkExtraScope { inherit flakeInputs self; };

      mkOpts = system:
        let
          perSystem  = mkPerSystem flakeInputs self system;
          extraScope = mkExtraScope { inherit flakeInputs self perSystem; };
        in
        mkOptions {
          inherit descriptors discovered configOptions extraScope agnosticScope flakeInputs self;
        } { inherit system; pkgs = nixpkgsFor system; };

      firstSystem  = head systems;
      firstEvaled  = loaded { options = mkOpts firstSystem; };
      agnosticByName    = collectAgnosticByName { inherit descriptors; evaled = firstEvaled; };
      agnosticFromMods  = foldl' (acc: r: acc // r) {} (attrValues agnosticByName);
      firstResult  = collectPerSystem { inherit descriptors; evaled = firstEvaled; system = firstSystem; agnosticResults = agnosticByName; };

      otherResults = listToAttrs (map (sys:
        let overridden = firstEvaled.override { options = mkOpts sys; };
        in { name = sys; value = collectPerSystem { inherit descriptors; evaled = overridden; system = sys; agnosticResults = agnosticByName; }; }
      ) (tail systems));

      transposed        = transpose ({ ${firstSystem} = firstResult; } // otherResults);
      templatesOutput   = buildTemplates (discoverTemplates resolvedSrc);
      libOutput         = importLib { libPath = discoverLib resolvedSrc; flake = self; inputs = allInputs; };
    in
    transposed // agnosticFromMods
    // (if templatesOutput != {} then { templates = templatesOutput; } else {})
    // (if libOutput != {} then { lib = libOutput; } else {});

  # ── Traditional entry point ─────────────────────────────────────────

  eval =
    { pkgs, src
    , extraModules ? {}, config ? {}, extraScope ? {}
    }:
    let
      system        = pkgs.system or pkgs.stdenv.hostPlatform.system;
      descriptors   = coreDescriptors // extraModules;
      discovered    = runDiscover src descriptors;
      configOptions = mkConfigOptions config;
      modules       = mkModules descriptors discovered;
      loaded        = adios { name = "red-tape"; inherit modules; };

      opts    = mkOptions { inherit descriptors discovered configOptions extraScope; }
                  { inherit system pkgs; };
      evaled  = loaded { options = opts; };
      agnosticByName = collectAgnosticByName { inherit descriptors evaled; };
      agnostic = foldl' (acc: r: acc // r) {} (attrValues agnosticByName);
      result  = collectPerSystem { inherit descriptors evaled system; agnosticResults = agnosticByName; };

      templatesOutput = buildTemplates (discoverTemplates src);
      libOutput       = importLib { libPath = discoverLib src; };
    in
    result // agnostic
    // { shell = result.devShells.default or null; }
    // (if templatesOutput != {} then { templates = templatesOutput; } else {})
    // (if libOutput != {} then { lib = libOutput; } else {});

in
{
  inherit mkFlake eval adios;

  # Exposed for tests — not part of the public API
  _internal = {
    inherit scanDir scanHosts filterPlatforms transpose
            buildTemplates callFile runDiscover discover coreDescriptors
            discoverTemplates discoverLib coreHostTypes;
    modules = {
      inherit modNixpkgs modPackages modDevshells modChecks
              modFormatter modOverlays modHosts modModulesExport;
    };
  };
}
