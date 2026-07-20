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
    # niri session: gnome backend delegates UI/filesystem interfaces to
    # GNOME Shell, which is absent here (fails as "not activatable"). Pin
    # those to gtk; keep PipeWire/desktop-integration interfaces on gnome.
    config.niri = {
      default = [ "gnome" "gtk" ];

      "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
      "org.freedesktop.impl.portal.AppChooser"  = [ "gtk" ];
      "org.freedesktop.impl.portal.OpenURI"     = [ "gtk" ];
      "org.freedesktop.impl.portal.Print"       = [ "gtk" ];
      "org.freedesktop.impl.portal.Settings"    = [ "gtk" ];

      "org.freedesktop.impl.portal.ScreenCast"    = [ "gnome" ];
      "org.freedesktop.impl.portal.RemoteDesktop" = [ "gnome" ];
      "org.freedesktop.impl.portal.Screenshot"    = [ "gnome" ];

      "org.freedesktop.impl.portal.Background"   = [ "gnome" ];
      "org.freedesktop.impl.portal.Inhibit"      = [ "gnome" ];
      "org.freedesktop.impl.portal.Notification" = [ "gnome" ];
      "org.freedesktop.impl.portal.Wallpaper"    = [ "gnome" ];

      "org.freedesktop.impl.portal.Access"          = [ "gnome" ];
      "org.freedesktop.impl.portal.Account"         = [ "gnome" ];
      "org.freedesktop.impl.portal.Lockdown"        = [ "gnome" ];
      "org.freedesktop.impl.portal.DynamicLauncher" = [ "gnome" ];

      # No real wlroots backend yet; list explicitly for predictable routing.
      "org.freedesktop.impl.portal.GlobalShortcuts" = [ "gnome" "gtk" ];
    };
  };
}