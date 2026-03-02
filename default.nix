# red-tape — Convention-based Nix project builder on adios-flake
#
# Usage:  outputs = inputs: inputs.red-tape.lib { inherit inputs; };
{ adios-flake }:
let
  inherit (builtins) isPath isString mapAttrs;

  # Normalize: accept either a flake input ({ lib.mkFlake = ...; }) or raw { mkFlake }
  adiosFlakeLib = adios-flake.lib or adios-flake;

  # ── Load orthogonal modules ────────────────────────────────────────
  discover       = import ./discover.nix;
  inherit (import ./call-file.nix) callFile;
  util           = import ./util.nix;
  inherit (util) withPrefix filterPlatforms;

  buildPackages     = import ./builders/packages.nix    { inherit callFile filterPlatforms withPrefix; };
  buildDevshells    = import ./builders/devshells.nix    { inherit callFile withPrefix; };
  buildChecks       = import ./builders/checks.nix       { inherit callFile filterPlatforms; };
  buildFormatter    = import ./builders/formatter.nix    { inherit callFile; };
  buildOverlays     = import ./builders/overlays.nix     { inherit callFile; };
  buildHosts        = import ./builders/hosts.nix        { inherit withPrefix; };
  buildModules      = import ./builders/modules-export.nix;
  buildTemplates    = import ./builders/templates.nix;
  importLib         = import ./builders/lib-export.nix;

  # ── Flake entry point ──────────────────────────────────────────────
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
      allInputs   = flakeInputs // (if self != null then { inherit self; } else {});

      resolvedSrc =
        if prefix != null then
          if isPath prefix then prefix
          else if isString prefix then src + "/${prefix}"
          else throw "red-tape: prefix must be a string or path"
        else src;

      found = discover.discoverAll resolvedSrc;

      # ── Build the scope for per-system callFile ──
      mkScope = pkgs: system: {
        inherit pkgs system;
        lib = pkgs.lib;
        flake = self;
        inputs = allInputs;
        perSystem = mapAttrs (_: input:
          if builtins.isAttrs input
          then (input.legacyPackages.${system} or {}) // (input.packages.${system} or {})
          else input
        ) allInputs;
      };

      # ── System-agnostic scope (for overlays) ──
      agnosticScope = {
        flake = self;
        inputs = allInputs;
      };

      # ── Resolve nixpkgs with optional config/overlays ──
      hasCustomNixpkgs =
        (nixpkgs.config or {}) != {} || (nixpkgs.overlays or []) != [];

      customNixpkgsFor = system:
        import inputs.nixpkgs {
          inherit system;
          config = nixpkgs.config or {};
          overlays = nixpkgs.overlays or [];
        };

      # ── Per-system builder: produces the adios-flake perSystem result ──
      perSystemFromDiscovery = { pkgs, system, ... }:
        let
          effectivePkgs = if hasCustomNixpkgs then customNixpkgsFor system else pkgs;
          scope = mkScope effectivePkgs system;

          pkg = if found.packages != null
            then buildPackages { discovered = found.packages; inherit scope system; }
            else { packages = {}; autoChecks = {}; };

          dev = if found.devshells != null
            then buildDevshells { discovered = found.devshells; inherit scope; }
            else { devShells = {}; autoChecks = {}; };

          chk = if found.checks != null
            then buildChecks { discovered = found.checks; inherit scope system; }
            else { checks = {}; };

          fmt = buildFormatter {
            formatterPath = found.formatter;
            inherit scope;
            pkgs = effectivePkgs;
          };

          # Merge auto-checks (packages, devshells) with user-defined checks.
          # User checks take precedence.
          allChecks = pkg.autoChecks // dev.autoChecks // chk.checks;
        in
        {
          inherit (pkg) packages;
          inherit (dev) devShells;
          formatter = fmt;
          checks = allChecks;
        };

      # ── Compose the perSystem function ──
      # If user provided a perSystem, merge its results with discovery.
      composedPerSystem =
        if perSystem != null then
          args:
            let
              disc = perSystemFromDiscovery args;
              user = perSystem args;
            in
            disc // user // {
              # Deep-merge attrset categories so user additions don't clobber discovery
              packages  = disc.packages  // (user.packages or {});
              devShells = disc.devShells // (user.devShells or {});
              checks    = disc.checks    // (user.checks or {});
            }
        else
          perSystemFromDiscovery;

      # ── System-agnostic outputs ──
      ovl = if found.overlays != null
        then buildOverlays { discovered = found.overlays; scope = agnosticScope; }
        else {};

      hosts = if found.hosts != null
        then buildHosts { discovered = found.hosts; inherit flakeInputs self; }
        else {};

      modExport = if found.modules != null
        then buildModules { discovered = found.modules; inherit flakeInputs self; extraTypeAliases = moduleTypeAliases; }
        else {};

      templates = let t = buildTemplates found.templates;
        in if t != {} then { templates = t; } else {};

      libExport = let l = importLib { libPath = found.lib; flake = self; inputs = allInputs; };
        in if l != {} then { lib = l; } else {};

      # ── Compose the flake parameter ──
      # Merge system-agnostic outputs from discovery with user-provided flake attrs.
      discoveredFlake =
        (builtins.removeAttrs ovl [ "autoChecks" ])
        // (builtins.removeAttrs hosts [ "autoChecks" ])
        // modExport
        // templates
        // libExport;

      composedFlake =
        if builtins.isFunction flake then
          { withSystem }:
            let userFlake = flake { inherit withSystem; };
            in discoveredFlake // userFlake
        else
          discoveredFlake // flake;

      # ── Host auto-checks need to be wired into perSystem ──
      # Hosts are system-agnostic but their checks are per-system.
      hostAutoChecks = if found.hosts != null then hosts.autoChecks else (_: {});

      finalPerSystem = args @ { pkgs, system, ... }:
        let
          base = composedPerSystem args;
          hChecks = hostAutoChecks system;
        in
        base // {
          checks = hChecks // base.checks;
        };

    in
    adiosFlakeLib.mkFlake {
      inherit inputs self systems config modules;
      perSystem = finalPerSystem;
      flake = composedFlake;
    };

in
{
  inherit mkFlake;

  # Exposed for tests and contrib modules
  _internal = {
    inherit discover callFile util;
    builders = {
      inherit buildPackages buildDevshells buildChecks buildFormatter
              buildOverlays buildHosts buildModules buildTemplates importLib;
    };
  };
}
