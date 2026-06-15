{ pkgs, ... }:

{
  home.packages = with pkgs; [
    zrythm
    ardour
    audacity
    gimp
    godot_4
    blender
  ];
}
