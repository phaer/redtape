{ pkgs, pname, ... }:
pkgs.writeShellScriptBin pname ''
  echo "Goodbye from ${pname}!"
''
