{ pkgs, ... }: pkgs.mkShell { packages = [ pkgs.custom-tool ]; }
