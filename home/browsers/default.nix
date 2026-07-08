{ pkgs, ... }:
{
  imports = [
    ./zen.nix
  ];

  home.packages = [
    pkgs.vivaldi
  ];
}
