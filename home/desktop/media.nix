{ pkgs, ... }:
{
  home.packages = [
    pkgs.vlc
    pkgs.splayer
    pkgs.pear-desktop
  ];
}
