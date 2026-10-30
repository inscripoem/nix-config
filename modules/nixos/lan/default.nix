# LAN environment class.
# Assumes the machine lives on a trusted local network.
# Provides mDNS via avahi for .local hostname resolution.
{ ... }:
{
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    settings.publish = {
      # nixpkgs renamed the `services.avahi.publish.*` options to these
      # settings and flipped the defaults: `disable-publishing` now
      # defaults to true, so both publishing controls must be explicit.
      disable-publishing = false;
      disable-user-service-publishing = false;
      publish-addresses = true;
      publish-workstation = true;
    };
  };
}
