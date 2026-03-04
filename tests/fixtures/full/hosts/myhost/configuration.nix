{ hostName, ... }:
{
  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "24.11";
  networking.hostName = hostName;
  services.nginx.enable = true;
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
