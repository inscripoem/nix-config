{ config, pkgs, ... }:

{
  # Use gnome-keyring as the Secret Service provider (org.freedesktop.secrets)
  # so libsecret-based apps (trae-cn, vivaldi, chromium, vscode, git) get an
  # auto-unlocked keyring at login. KWallet stays for KDE-internal use only.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;
}