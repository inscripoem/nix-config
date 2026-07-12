{ config, pkgs, ... }:

{
  networking.networkmanager.enable = true;

  services.openssh.enable = true;

  # Sunshine opens its own ports (47984–48010) via
  # services.sunshine.openFirewall = true in sunshine.nix; we deliberately
  # do NOT duplicate them here. openFirewall in services.tailscale only
  # opens UDP 41641 (WireGuard), not application ports.

  # mDNS: publish briefcase.local so other machines on the LAN can
  # resolve this host by name without knowing its IP. Without
  # publish.addresses the avahi daemon runs but stays silent —
  # briefcase.local has no A record, so RDP/SSH/etc. clients that
  # connect by hostname fail at DNS resolution before even reaching
  # the firewall.
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
