{ config, pkgs, ... }:

{
  # Enable DankMaterialShell - desktop shell for niri.
  # NOTE: systemd.enable is intentionally false. The upstream module would
  # bind dms.service to graphical-session.target, which is also activated by
  # KDE Plasma and COSMIC sessions, causing the niri taskbar to appear on
  # top of those desktops. We start dms from niri's spawn-at-startup
  # instead (see home/desktop/niri.nix) so it only runs inside niri.
  programs.dms-shell = {
    enable = true;
    systemd.enable = false;
    enableSystemMonitoring = true;
    enableDynamicTheming = true;
  };
}