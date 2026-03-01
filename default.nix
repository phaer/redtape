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

  scanHosts = path:
    let
      detectType = hostPath:
        if pathExists (hostPath + "/default.nix") then
          { type = "custom"; configPath = hostPath + "/default.nix"; }
        else if pathExists (hostPath + "/configuration.nix") then
          { type = "nixos"; configPath = hostPath + "/configuration.nix"; }
        else if pathExists (hostPath + "/darwin-configuration.nix") then
          { type = "darwin"; configPath = hostPath + "/darwin-configuration.nix"; }
        else null;
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

  discover = src: {
    packages  = scanDir (src + "/packages") // optionalFile (src + "/package.nix") "default";
    devshells = scanDir (src + "/devshells") // optionalFile (src + "/devshell.nix") "default";
    checks    = scanDir (src + "/checks");
    formatter = optionalPath (src + "/formatter.nix");
    overlays  = scanDir (src + "/overlays") // optionalFile (src + "/overlay.nix") "default";
    hosts     = scanHosts (src + "/hosts");
    modules   = scanModuleTypes (src + "/modules");
    templates = scanTemplates (src + "/templates");
    lib       = optionalPath (src + "/lib/default.nix");
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
    options = {
      system = { type = types.string; };
      pkgs   = { type = types.attrs; };
    };
  };

  # Generic per-system module factory
  mkPerSystemMod = { name, postProcess ? ({ built, ... }: built) }: {
    inherit name;
    inputs.nixpkgs = { path = "/nixpkgs"; };
    options = {
      discovered = { type = types.attrs; default = {}; };
      extraScope = { type = types.attrs; default = {}; };
    };
    impl = { inputs, options, ... }:
      let
        system = inputs.nixpkgs.system;
        pkgs = inputs.nixpkgs.pkgs;
        scope = { inherit pkgs system; lib = pkgs.lib; } // options.extraScope;
        built = mapAttrs (pname: entry:
          let path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
          in callFile scope path { inherit pname; }
        ) options.discovered;
      in
      postProcess { inherit system pkgs built; };
  };

  modPackages = mkPerSystemMod {
    name = "packages";
    postProcess = { system, built, ... }:
      { packages = built; filteredPackages = filterPlatforms system built; };
  };

  modDevshells = mkPerSystemMod {
    name = "devshells";
    postProcess = { built, ... }: { devShells = built; };
  };

  modChecks = mkPerSystemMod {
    name = "checks";
    postProcess = { system, built, ... }: { checks = filterPlatforms system built; };
  };

  modFormatter = {
    name = "formatter";
    inputs.nixpkgs = { path = "/nixpkgs"; };
    options = {
      formatterPath = { type = types.any; default = null; };
      extraScope     = { type = types.attrs; default = {}; };
    };
    impl = { inputs, options, ... }:
      let
        pkgs = inputs.nixpkgs.pkgs;
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
    name = "overlays";
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

  classMap = { "nixos" = "nixosConfigurations"; "nix-darwin" = "darwinConfigurations"; };

  modHosts = {
    name = "hosts";
    options = {
      discovered   = { type = types.attrs; default = {}; };
      flakeInputs  = { type = types.attrs; default = {}; };
      self         = { type = types.any;   default = null; };
    };
    impl = { options, ... }:
      let
        inherit (options) flakeInputs self;
        allInputs = flakeInputs // (if self != null then { inherit self; } else {});
        specialArgs = { flake = self; inputs = allInputs; };

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
                modules = [ hostInfo.configPath ];
                specialArgs = specialArgs // { inherit hostName; };
              };
            }
            else if hostInfo.type == "darwin" then
              let nix-darwin = flakeInputs.nix-darwin
                or (throw "red-tape: host '${hostName}' needs inputs.nix-darwin");
              in {
                class = "nix-darwin";
                value = nix-darwin.lib.darwinSystem {
                  modules = [ hostInfo.configPath ];
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
    name = "modules-export";
    options = {
      discovered   = { type = types.attrs; default = {}; };
      flakeInputs  = { type = types.attrs; default = {}; };
      self         = { type = types.any;   default = null; };
    };
    impl = { options, ... }:
      let
        inherit (options) flakeInputs self;
        allInputs = flakeInputs // (if self != null then { inherit self; } else {});
        publisherArgs = { flake = self; inputs = allInputs; };

        expectsPublisherArgs = fn:
          let args = functionArgs fn;
          in isFunction fn && args != {}
          && all (arg: elem arg (attrNames publisherArgs)) (attrNames args);

        importModule = entry:
          let
            path = if entry.type == "directory" then entry.path + "/default.nix" else entry.path;
            mod = import path;
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

  mkModules = { discovered, extraModules ? {} }:
    { nixpkgs = modNixpkgs; formatter = modFormatter; }
    // (if discovered.packages  != {} then { packages       = modPackages; }      else {})
    // (if discovered.devshells != {} then { devshells      = modDevshells; }     else {})
    // (if discovered.checks    != {} then { checks         = modChecks; }        else {})
    // (if discovered.hosts     != {} then { hosts          = modHosts; }         else {})
    // (if discovered.overlays  != {} then { overlays       = modOverlays; }      else {})
    // (if discovered.modules   != {} then { modules-export = modModulesExport; } else {})
    // extraModules;

  mkExtraScope = { flakeInputs ? {}, self ? null, perSystem ? {} }:
    let allInputs = mkAllInputs flakeInputs self;
    in { inherit perSystem; }
    // (if self != null then { flake = self; } else {})
    // (if allInputs != {} then { inputs = allInputs; } else {});

  mkConfigOptions = config:
    listToAttrs (map (key: { name = "/${key}"; value = config.${key}; }) (attrNames config));

  mkOptions =
    { modules, discovered, configOptions
    , extraScope ? {}, agnosticScope ? {}
    , flakeInputs ? {}, self ? null
    }: nixpkgsOpt:
    { "/nixpkgs"    = nixpkgsOpt;
      "/formatter"  = { formatterPath = discovered.formatter; inherit extraScope; };
    }
    // (if modules ? packages  then { "/packages"  = { discovered = discovered.packages;  inherit extraScope; }; } else {})
    // (if modules ? devshells then { "/devshells" = { discovered = discovered.devshells; inherit extraScope; }; } else {})
    // (if modules ? checks    then { "/checks"    = { discovered = discovered.checks;    inherit extraScope; }; } else {})
    // (if modules ? hosts     then { "/hosts"          = { discovered = discovered.hosts;   inherit flakeInputs self; }; } else {})
    // (if modules ? overlays  then { "/overlays"       = { discovered = discovered.overlays; extraScope = agnosticScope; }; } else {})
    // (if modules ? modules-export then { "/modules-export" = { discovered = discovered.modules; inherit flakeInputs self; }; } else {})
    // configOptions;

  # ── Result collection ──────────────────────────────────────────────

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
          in map (tname: {
            name = "pkgs-${pname}-${tname}";
            value = tests.${tname};
          }) (attrNames tests)
        ) (attrNames pkgResult.filteredPackages));
    in {
      packages  = pkgResult.filteredPackages;
      devShells = devResult.devShells;
      formatter = fmtResult.formatter;
      checks    = packageChecks // withPrefix "devshell-" devResult.devShells // chkResult.checks;
    };

  # Known per-system module names — their results are transposed, not merged here
  perSystemModuleNames = [ "nixpkgs" "packages" "devshells" "formatter" "checks" ];

  collectAgnostic = evaled:
    let
      mods = evaled.modules;
      has = name: mods ? ${name};
      hostResult   = if has "hosts"          then mods.hosts {}          else {};
      ovlResult    = if has "overlays"       then mods.overlays {}       else {};
      modExpResult = if has "modules-export" then mods.modules-export {} else {};

      # Collect results from any extra modules not handled above.
      # Users can add custom system-agnostic modules via extraModules and their
      # results are automatically merged into the top-level flake outputs.
      knownNames = perSystemModuleNames ++ [ "hosts" "overlays" "modules-export" ];
      extraResults = foldl' (acc: name:
        if elem name knownNames then acc
        else acc // (mods.${name} {})
      ) {} (attrNames mods);
    in
    extraResults
    // hostResult
    // (if ovlResult != {} then { overlays = ovlResult.overlays; } else {})
    // modExpResult;

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

      discovered    = discover resolvedSrc;
      configOptions = mkConfigOptions config;
      modules       = mkModules { inherit discovered extraModules; };
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
          inherit modules discovered configOptions extraScope agnosticScope flakeInputs self;
        } { inherit system; pkgs = nixpkgsFor system; };

      firstSystem  = head systems;
      firstEvaled  = loaded { options = mkOpts firstSystem; };
      firstResult  = collectPerSystem { evaled = firstEvaled; system = firstSystem; };

      otherResults = listToAttrs (map (sys:
        let overridden = firstEvaled.override { options = mkOpts sys; };
        in { name = sys; value = collectPerSystem { evaled = overridden; system = sys; }; }
      ) (tail systems));

      transposed        = transpose ({ ${firstSystem} = firstResult; } // otherResults);
      agnosticFromMods  = collectAgnostic firstEvaled;
      templatesOutput   = buildTemplates discovered.templates;
      libOutput         = importLib { libPath = discovered.lib; flake = self; inputs = allInputs; };
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
      discovered    = discover src;
      configOptions = mkConfigOptions config;
      modules       = mkModules { inherit discovered extraModules; };
      loaded        = adios { name = "red-tape"; inherit modules; };

      opts    = mkOptions { inherit modules discovered configOptions extraScope; }
                  { inherit system pkgs; };
      evaled  = loaded { options = opts; };
      result  = collectPerSystem { inherit evaled system; };
      agnostic = collectAgnostic evaled;

      templatesOutput = buildTemplates discovered.templates;
      libOutput       = importLib { libPath = discovered.lib; };
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
    inherit discover scanDir scanHosts filterPlatforms transpose
            buildTemplates callFile;
    modules = {
      inherit modNixpkgs modPackages modDevshells modChecks
              modFormatter modOverlays modHosts modModulesExport;
    };
  };
}
