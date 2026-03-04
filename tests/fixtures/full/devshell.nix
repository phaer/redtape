{ pkgs, ... }: pkgs.mkShell { packages = [ pkgs.jq ]; }
