{ pkgs, ... }:

{
  home.packages = [
    pkgs.devenv
    pkgs.tokei
  ];
}
