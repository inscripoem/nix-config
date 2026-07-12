{ config, lib, pkgs, ... }:
let cfg = config.modules.capabilities.gaming;
in {
  options.modules.capabilities.gaming.enable =
    lib.mkEnableOption "gaming suite (Steam, Proton-GE, gamemode)";
  config = lib.mkIf cfg.enable {
    # P2: programs.steam, programs.gamemode
  };
}
