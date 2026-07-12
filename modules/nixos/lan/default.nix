# LAN environment class.
# Assumes the machine lives on a trusted local network.
# Provides mDNS via avahi for .local hostname resolution.
{ ... }:
{
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };
}
