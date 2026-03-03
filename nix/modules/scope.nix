# red-tape/scope — Build shared evaluation scope for per-system modules
#
# Inputs: /nixpkgs (system, pkgs), ../scan (discovery + flake context)
# Result: { system, pkgs, self, allInputs, scope }
#
# Downstream per-system modules (packages, devshells, checks, formatter)
# depend on ../scope to get the evaluation scope without duplicating it.
{
  name = "scope";
  inputs = {
    nixpkgs = { path = "/nixpkgs"; };
    scan    = { path = "../scan"; };
  };
  impl = { inputs, results, ... }:
    let
      inherit (builtins) isAttrs mapAttrs;
      system = inputs.nixpkgs.system;
      pkgs = inputs.nixpkgs.pkgs;
      inherit (results.scan) self allInputs;
    in
    {
      inherit system pkgs self allInputs;
      scope = {
        inherit system pkgs;
        lib = pkgs.lib;
        flake = self;
        inputs = allInputs;
        perSystem = mapAttrs (_: i:
          if isAttrs i then (i.legacyPackages.${system} or {}) // (i.packages.${system} or {}) else i
        ) allInputs;
      };
    };
}
