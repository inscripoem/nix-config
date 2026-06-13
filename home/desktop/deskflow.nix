{ pkgs, ... }:

{
  home.packages = with pkgs; [
    deskflow
  ];

  xdg.configFile."autostart/org.deskflow.deskflow.desktop".source =
    "${pkgs.deskflow}/share/applications/org.deskflow.deskflow.desktop";
}
