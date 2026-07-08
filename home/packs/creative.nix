{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ardour
    audacity
    blender
    gimp
    godot_4
    zrythm
  ];
}