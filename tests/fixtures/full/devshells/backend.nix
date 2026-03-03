{ pkgs, ... }:
pkgs.mkShell {
  packages = [ pkgs.nodejs ];
}
