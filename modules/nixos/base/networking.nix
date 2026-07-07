{ config, pkgs, ... }:

{
  networking.networkmanager.enable = true;

  services.openssh.enable = true;

  # LocalSend needs port 53317 on both TCP (file transfer) and UDP
  # (multicast peer discovery). Without this, receiving works only via
  # manual IP entry and other devices cannot auto-discover this host.
  networking.firewall.allowedTCPPorts = [ 53317 ];
  networking.firewall.allowedUDPPorts = [ 53317 ];
}
