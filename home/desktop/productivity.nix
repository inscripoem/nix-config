{ pkgs, ... }:
{
  imports = [
    ./siyuan.nix
  ];

  home.packages = [
    pkgs.libreoffice
    pkgs.localsend
    pkgs.notion-electron
  ];
}