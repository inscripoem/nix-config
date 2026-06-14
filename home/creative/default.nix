{ pkgs, ... }:

{
  home.packages = with pkgs; [
    zrythm
  ];
}
