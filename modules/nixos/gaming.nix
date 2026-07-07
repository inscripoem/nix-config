{ pkgs, ... }:

{
  programs.steam = {
    enable = true;
    # https://github.com/GloriousEggroll/proton-ge-custom
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  programs.gamemode.enable = true;
}
