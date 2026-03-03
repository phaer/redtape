# contrib/system-manager.nix — system-manager host support
# https://github.com/numtide/system-manager
_: {
  "/red-tape/scan".extraHostTypes = [
    {
      type = "system-manager";
      file = "system-configuration.nix";
    }
  ];
  "/red-tape/hosts".extraHostTypes.system-manager = {
    outputKey = "systemConfigs";
    build =
      {
        name,
        info,
        specialArgs,
        inputs,
      }:
      let
        sm =
          inputs.system-manager or (throw "red-tape: system-manager contrib needs inputs.system-manager");
      in
      builtins.addErrorContext "while building system-manager host '${name}'" (
        sm.lib.makeSystemConfig {
          modules = [ info.configPath ];
          specialArgs = specialArgs // {
            hostName = name;
          };
        }
      );
  };
}
