{ hostName, ... }:
{
  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "24.11";
  networking.hostName = hostName;
  services.postgresql = {
    enable = true;
    settings = {
      max_connections = 200;
      shared_buffers = "256MB";
    };
  };
  networking.firewall.allowedTCPPorts = [ 5432 ];
}
