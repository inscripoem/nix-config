{ config, pkgs, ... }:

{
  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Enable COSMIC desktop environment (parallel install with KDE Plasma).
  services.desktopManager.cosmic.enable = true;

  # Enable niri - scrollable-tiling Wayland compositor
  programs.niri.enable = true;
}