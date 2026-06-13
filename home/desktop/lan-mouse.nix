{ pkgs, ... }:

{
  home.packages = with pkgs; [
    lan-mouse
  ];

  # xdg.configFile."autostart/de.feschber.LanMouse.desktop".source =
  #   "${pkgs.lan-mouse}/share/applications/de.feschber.LanMouse.desktop";
}
