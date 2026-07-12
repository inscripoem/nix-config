# Base SSH — permissive defaults for trusted local hosts.
#
# Why permissive:
#   All current hosts run on the local LAN or tailnet. Password auth
#   and root login (prohibit-password, i.e. key-only for root) are
#   convenient defaults that still protect against brute-force from
#   untrusted networks.
#
# X11Forwarding and further hardening are layered by class modules:
#   - desktop/ssh-x11.nix enables X11 forwarding for GUI hosts.
#   - public/default.nix will harden SSH for internet-facing servers.
{ ... }:
{
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "prohibit-password";   # key-only for colmena/deploy-rs
      PasswordAuthentication = true;             # local convenience
    };
  };
}
