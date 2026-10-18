{ pkgs, ... }:

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

  # Enable niri - scrollable-tiling Wayland compositor.
  # Use niri-unstable from the niri-flake overlay to get newer actions like
  # maximize-window-to-edges that are not yet in the stable release.
  programs.niri = {
    enable = true;
    package = pkgs.niri-unstable;
  };
  # niri-flake hardcodes a polkit-kde-agent user service into every niri
  # session. polkitd allows exactly one registered agent per session, so the
  # always-running KDE agent beats the one DMS (quickshell) registers on shell
  # startup, and pkexec prompts render Kirigami-styled (light window, dark
  # buttons) instead of following DMS's theme. Disable it: DMS's built-in
  # PolkitAgent is the sole agent under niri; Plasma sessions are unaffected —
  # the plasma6 module ships the same agent via its OnlyShowIn=KDE autostart
  # entry, which niri sessions skip.
  systemd.user.services.niri-flake-polkit.enable = false;
  # niri session doesn't pull GNOME; install nautilus so
  # xdg-desktop-portal-gnome (≥ v47) can back its FileChooser.
  # See https://github.com/YaLTeR/niri/wiki/Important-Software#portals.
  environment.systemPackages = [ pkgs.nautilus ];

  # LocalSend needs port 53317 on both TCP (file transfer) and UDP
  # (multicast peer discovery).
  networking.firewall.allowedTCPPorts = [ 53317 ];
  networking.firewall.allowedUDPPorts = [ 53317 ];
}