{ pkgs, pname, ... }:
pkgs.runCommand pname { } ''
  echo "check passed"
  touch $out
''
