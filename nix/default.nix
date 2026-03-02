# red-tape — Convention-based Nix project builder on adios-flake
#
# Usage:  outputs = inputs: inputs.red-tape.lib { inherit inputs; };
{ adios-flake }:
let
  inherit (builtins)
    addErrorContext all attrNames concatMap elem filter
    foldl' functionArgs intersectAttrs isAttrs isFunction
    isPath isString listToAttrs map mapAttrs pathExists;

  adiosFlakeLib = adios-flake.lib or adios-flake;
  discover = import ./discover.nix;

  # ── Primitives ─────────────────────────────────────────────────────
  #
  #   callFile      — import a .nix file, auto-inject from scope
  #   entryPath     — resolve a discovered entry to its .nix path
  #   buildAll      — callFile over every discovered entry
  #   withPrefix    — prefix all keys in an attrset
  #   filterPlatforms — keep only derivations matching system

  callFile = scope: path: extra:
    addErrorContext "while evaluating '${toString path}'" (
      let fn = import path;
      in fn (intersectAttrs (functionArgs fn) (scope // extra))
    );

  entryPath = e: if e.type == "directory" then e.path + "/default.nix" else e.path;

  buildAll = scope: mapAttrs (pname: e: callFile scope (entryPath e) { inherit pname; });

  withPrefix = pre: a: listToAttrs (map (n: { name = "${pre}${n}"; value = a.${n}; }) (attrNames a));

  filterPlatforms = system: a:
    listToAttrs (filter (x: x != null) (map (n:
      let p = a.${n}.meta.platforms or [];
      in if p == [] || elem system p then { name = n; value = a.${n}; } else null
    ) (attrNames a)));

  # Merge inputs, adding self if present.
  mkAllInputs = flakeInputs: self:
    flakeInputs // (if self != null then { inherit self; } else {});

  # ── Module export ──────────────────────────────────────────────────

  defaultTypeAliases = { nixos = "nixosModules"; darwin = "darwinModules"; home = "homeModules"; };

  buildModules = { discovered, allInputs, self, extraTypeAliases ? {} }:
    let
      publisherArgs = { flake = self; inputs = allInputs; };
      typeAliases = defaultTypeAliases // extraTypeAliases;

      isPublisherFn = fn:
        isFunction fn && (functionArgs fn) != {}
        && all (a: elem a [ "flake" "inputs" ]) (attrNames (functionArgs fn));

      importModule = e:
        let path = entryPath e; mod = import path;
        in if isPublisherFn mod
          then { _file = toString path; imports = [ (mod (intersectAttrs (functionArgs mod) publisherArgs)) ]; }
          else path;

      built = mapAttrs (_: mapAttrs (_: importModule)) discovered;
    in
    foldl' (acc: t:
      let alias = typeAliases.${t} or null;
      in if alias != null then acc // { ${alias} = built.${t}; } else acc
    ) {} (attrNames discovered);

  # ── Host configurations ────────────────────────────────────────────

  buildHosts = { discovered, allInputs, self }:
    let
      specialArgs = { flake = self; inputs = allInputs; };
      outputKey = { nixos = "nixosConfigurations"; nix-darwin = "darwinConfigurations"; };

      loadHost = name: info:
        addErrorContext "while building host '${name}' (${info.type})" (
          if info.type == "custom" then
            import info.configPath { inherit (specialArgs) flake inputs; hostName = name; }
          else if info.type == "nixos" then {
            class = "nixos";
            value = allInputs.nixpkgs.lib.nixosSystem {
              modules = [ info.configPath ];
              specialArgs = specialArgs // { hostName = name; };
            };
          }
          else if info.type == "darwin" then
            let nd = allInputs.nix-darwin or (throw "red-tape: host '${name}' needs inputs.nix-darwin");
            in { class = "nix-darwin"; value = nd.lib.darwinSystem {
              modules = [ info.configPath ];
              specialArgs = specialArgs // { hostName = name; };
            }; }
          else throw "red-tape: unknown host type '${info.type}' for '${name}'"
        );

      loaded = mapAttrs loadHost discovered;

      byClass = cls: listToAttrs (filter (x: x != null) (map (n:
        let h = loaded.${n};
        in if (outputKey.${h.class} or null) == cls then { name = n; value = h.value; } else null
      ) (attrNames loaded)));

      nixos  = byClass "nixosConfigurations";
      darwin = byClass "darwinConfigurations";

      autoChecks = system:
        let check = pre: hosts: listToAttrs (filter (x: x != null) (map (n:
              let s = hosts.${n}.config.nixpkgs.hostPlatform.system or null;
              in if s == system then { name = "${pre}-${n}"; value = hosts.${n}.config.system.build.toplevel; } else null
            ) (attrNames hosts)));
        in check "nixos" nixos // check "darwin" darwin;
    in
    { nixosConfigurations = nixos; darwinConfigurations = darwin; inherit autoChecks; };

  # ── mkFlake ────────────────────────────────────────────────────────

  mkFlake =
    { inputs
    , self ? inputs.self or null
    , src ? (if self != null then self else throw "red-tape: either self or src required")
    , prefix ? null
    , systems ? [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ]
    , nixpkgs ? {}
    , modules ? []
    , perSystem ? null
    , config ? {}
    , flake ? {}
    , moduleTypeAliases ? {}
    }:
    let
      flakeInputs = builtins.removeAttrs inputs [ "self" ];
      allInputs = mkAllInputs flakeInputs self;

      resolvedSrc =
        if prefix != null then
          (if isPath prefix then prefix else src + "/${prefix}")
        else src;

      found = discover.discoverAll resolvedSrc;

      mkScope = pkgs: system: {
        inherit pkgs system;
        lib = pkgs.lib;
        flake = self;
        inputs = allInputs;
        perSystem = mapAttrs (_: i:
          if isAttrs i then (i.legacyPackages.${system} or {}) // (i.packages.${system} or {}) else i
        ) allInputs;
      };

      hasCustomNixpkgs = (nixpkgs.config or {}) != {} || (nixpkgs.overlays or []) != [];
      customNixpkgsFor = system: import inputs.nixpkgs {
        inherit system; config = nixpkgs.config or {}; overlays = nixpkgs.overlays or [];
      };

      # ── Per-system ──
      perSystemFromDiscovery = { pkgs, system, ... }:
        let
          p = if hasCustomNixpkgs then customNixpkgsFor system else pkgs;
          scope = mkScope p system;
          packages  = filterPlatforms system (buildAll scope found.packages);
          devShells = buildAll scope found.devshells;
          checks    = filterPlatforms system (buildAll scope found.checks);
          formatter = if found.formatter != null then callFile scope found.formatter {}
            else p.nixfmt-tree or p.nixfmt or (throw "red-tape: no formatter.nix and nixfmt-tree unavailable");
          pkgChecks = withPrefix "pkgs-" packages
            // listToAttrs (concatMap (pname:
              let tests = filterPlatforms system (packages.${pname}.passthru.tests or {});
              in map (t: { name = "pkgs-${pname}-${t}"; value = tests.${t}; }) (attrNames tests)
            ) (attrNames packages));
        in {
          inherit packages devShells formatter;
          checks = pkgChecks // withPrefix "devshell-" devShells // checks;
        };

      composedPerSystem =
        if perSystem == null then perSystemFromDiscovery
        else args:
          let d = perSystemFromDiscovery args; u = perSystem args;
          in d // u // {
            packages  = d.packages  // (u.packages or {});
            devShells = d.devShells // (u.devShells or {});
            checks    = d.checks    // (u.checks or {});
          };

      # ── System-agnostic ──
      agnostic = { flake = self; inputs = allInputs; };

      hosts = if found.hosts != {} then buildHosts { discovered = found.hosts; inherit allInputs self; } else {};
      hostAutoChecks = hosts.autoChecks or (_: {});

      discoveredFlake =
        (if found.overlays != {} then { overlays = buildAll agnostic found.overlays; } else {})
        // (builtins.removeAttrs hosts [ "autoChecks" ])
        // (if found.modules != {} then buildModules { discovered = found.modules; inherit allInputs self; extraTypeAliases = moduleTypeAliases; } else {})
        // (let t = mapAttrs (name: e: { inherit (e) path; description =
              let f = e.path + "/flake.nix"; in if pathExists f then (import f).description or name else name;
            }) found.templates; in if t != {} then { templates = t; } else {})
        // (let l = if found.lib == null then {} else let m = import found.lib;
              in if isFunction m then m { flake = self; inputs = allInputs; } else m;
            in if l != {} then { lib = l; } else {});

      composedFlake =
        if isFunction flake then { withSystem }: discoveredFlake // flake { inherit withSystem; }
        else discoveredFlake // flake;

      finalPerSystem = args @ { pkgs, system, ... }:
        let base = composedPerSystem args;
        in base // { checks = hostAutoChecks system // base.checks; };

    in
    adiosFlakeLib.mkFlake {
      inherit inputs self systems config modules;
      perSystem = finalPerSystem;
      flake = composedFlake;
    };

in {
  inherit mkFlake;
  _internal = {
    inherit discover callFile buildAll entryPath withPrefix filterPlatforms;
    builders = { inherit buildModules buildHosts; };
  };
}
