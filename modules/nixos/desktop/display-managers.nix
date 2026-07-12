{ config, pkgs, ... }:

{
  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  # SDDM greeter must run on X11 (not Wayland) so that the root
  # sunshine-sddm system service can grab the greeter framebuffer via
  # XShm/XDamage. On a Wayland greeter there is no X server to capture.
  # See docs/remote-desktop.md §2.
  services.displayManager.sddm.wayland.enable = false;
  services.desktopManager.plasma6.enable = true;
  # For the sunshine-sddm handoff to work, the user session must start on
  # the same X display (:0) that SDDM created. plasmax11 is the only
  # xsessions entry on this box (`ls /run/current-system/sw/share/xsessions/`
  # → plasmax11.desktop).
  services.displayManager.defaultSession = "plasmax11";

  # No auto-login. Sunshine runs as a root system service
  # (sunshine-sddm) that captures the SDDM X11 greeter before anyone
  # logs in — Moonlight connects, sees the SDDM login screen, you type
  # the password, and the session hands off to the user-level Sunshine
  # service. This avoids the auto-login + keyring problem (KWallet /
  # gnome-keyring never unlock without a PAM password, which breaks WiFi
  # auto-connect and Vivaldi's cookie store). See docs/remote-desktop.md.

  # Enable COSMIC desktop environment (parallel install with KDE Plasma).
  services.desktopManager.cosmic.enable = true;

  # Enable niri - scrollable-tiling Wayland compositor
  programs.niri.enable = true;

  # LocalSend needs port 53317 on both TCP (file transfer) and UDP
  # (multicast peer discovery).
  networking.firewall.allowedTCPPorts = [ 53317 ];
  networking.firewall.allowedUDPPorts = [ 53317 ];
}