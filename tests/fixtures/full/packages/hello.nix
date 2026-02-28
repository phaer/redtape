{ pkgs, pname, ... }:
pkgs.writeShellScriptBin pname ''
  echo "Hello from ${pname}!"
''
