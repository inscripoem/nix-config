{ config, pkgs, ... }:

{
  # xdg-desktop-portal routing. xdg-desktop-portal-gtk gets pulled in by some
  # apps but it does NOT implement RemoteDesktop, so without an explicit
  # preference the router can fail to find a backend (e.g. deskflow client on
  # Wayland: "No such interface org.freedesktop.portal.RemoteDesktop").
  # Force every interface on a KDE session to the kde backend; KWin provides
  # RemoteDesktop via libei.
  # COSMIC session will use xdg-desktop-portal-cosmic automatically.
  xdg.portal = {
    enable = true;
    config.kde.default = [ "kde" ];
    config.cosmic.default = [ "cosmic" ];
    config.niri.default = [ "gnome" "gtk" ];
  };
}