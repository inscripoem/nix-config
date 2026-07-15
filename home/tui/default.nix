{ pkgs, ... }:

{
  imports = [
    ./pueue.nix
    ./tokei.nix
  ];

  home.packages = [
    pkgs.gh
  ];
}
