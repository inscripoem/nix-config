{ pkgs, ... }:

{
  home.packages = with pkgs; [
    deskflow
    # Required so deskflow can read/write the Wayland clipboard via
    # wl-copy / wl-paste; without this the "Clipboard sharing" toggle
    # in deskflow's settings is silently inert on Wayland sessions.
    wl-clipboard
  ];

  xdg.configFile."autostart/org.deskflow.deskflow.desktop".source =
    "${pkgs.deskflow}/share/applications/org.deskflow.deskflow.desktop";
}
