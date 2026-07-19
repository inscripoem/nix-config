{ config, pkgs, ... }:

{
  # xdg-desktop-portal routing. xdg-desktop-portal-gtk gets pulled in by some
  # apps but it does NOT implement RemoteDesktop, so without an explicit
  # preference the router can fail to find a backend (e.g. deskflow client on
  # Wayland: "No such interface org.freedesktop.portal.RemoteDesktop").
  # Force every interface on a KDE session to the kde backend; KWin provides
  # RemoteDesktop via libei.
  # COSMIC session will use xdg-desktop-portal-cosmic automatically.
  #
  # niri is a standalone compositor flake and does not register any portal
  # backend itself. Route its session to gnome (with gtk as fallback) and
  # add xdg-desktop-portal-gnome explicitly: plasma6 auto-adds the kde
  # portal, gtk is pulled in transitively, but gnome must be listed here
  # or the router falls back to gtk (which lacks ScreenCast/RemoteDesktop).
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
    config.kde.default = [ "kde" ];
    config.cosmic.default = [ "cosmic" ];
    config.niri.default = [ "gnome" "gtk" ];
  };
}