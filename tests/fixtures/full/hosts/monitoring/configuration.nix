{ hostName, ... }:
{
  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "24.11";
  networking.hostName = hostName;
  services.prometheus = {
    enable = true;
    globalConfig.scrape_interval = "15s";
  };
  services.grafana = {
    enable = true;
    settings.server.http_port = 3000;
  };
  networking.firewall.allowedTCPPorts = [ 9090 3000 ];
}
