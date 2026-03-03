# red-tape — Convention-based Nix project builder on adios-flake
#
# Primary API:
#   red-tape.lib.module { src = self; ... }       — adios-flake module (per-system)
#   red-tape.lib.flakeOutputs { src = self; ... }  — system-agnostic flake outputs
#
# Convenience:
#   red-tape.mkFlake { inherit inputs; }           — full flake via mkFlake wrapper
{ adios-flake }:
let
  inherit (builtins)
    addErrorContext all attrNames concatMap elem filter
    foldl' functionArgs intersectAttrs isAttrs isFunction
    isPath isString listToAttrs map mapAttrs pathExists;

  adiosFlakeLib = adios-flake.lib or adios-flake;
  discover = import ./discover.nix;

  # ── Primitives ─────────────────────────────────────────────────────

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

  # ── Public API: adios-flake module (per-system) ────────────────────

  module = import ./module.nix { inherit discover callFile buildAll filterPlatforms withPrefix; };

  # ── Public API: flake-level outputs (system-agnostic) ──────────────

  flakeOutputs = import ./flake-outputs.nix { inherit discover buildAll buildModules buildHosts; };

  # ── Convenience: mkFlake wrapper ───────────────────────────────────

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
      allInputs = flakeInputs // (if self != null then { inherit self; } else {});

      # Per-system: red-tape module + optional user perSystem
      redTapeModule = module { inherit src nixpkgs prefix inputs self; };

      composedPerSystem =
        if perSystem == null then redTapeModule
        else args:
          let d = redTapeModule args; u = perSystem args;
          in d // u // {
            packages  = d.packages  // (u.packages or {});
            devShells = d.devShells // (u.devShells or {});
            checks    = d.checks    // (u.checks or {});
          };

      # Flake-level: red-tape outputs + optional user flake
      redTapeFlake = flakeOutputs { inherit src inputs self prefix moduleTypeAliases; };

      composedFlake =
        if isFunction flake then { withSystem }: redTapeFlake // flake { inherit withSystem; }
        else redTapeFlake // flake;

      # Host auto-checks from nixos/darwin configurations in flake outputs
      nixos = redTapeFlake.nixosConfigurations or {};
      darwin = redTapeFlake.darwinConfigurations or {};
      hostAutoChecks = system:
        let check = pre: cfgs: builtins.listToAttrs (builtins.filter (x: x != null) (builtins.map (n:
              let s = cfgs.${n}.config.nixpkgs.hostPlatform.system or null;
              in if s == system then { name = "${pre}-${n}"; value = cfgs.${n}.config.system.build.toplevel; } else null
            ) (builtins.attrNames cfgs)));
        in check "nixos" nixos // check "darwin" darwin;

      # Inject host auto-checks into per-system checks
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
  inherit mkFlake module flakeOutputs;
  _internal = {
    inherit discover callFile buildAll entryPath withPrefix filterPlatforms;
    builders = { inherit buildModules buildHosts; };
  };
}
