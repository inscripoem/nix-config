{ config, lib, pkgs, ... }:
let cfg = config.modules.capabilities.gaming;
in {
  options.modules.capabilities.gaming.enable =
    lib.mkEnableOption "gaming suite (Steam, Proton-GE, gamemode)";
  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      # https://github.com/GloriousEggroll/proton-ge-custom
      extraCompatPackages = [ pkgs.proton-ge-bin ];
    };
    programs.gamemode.enable = true;
  };
}
