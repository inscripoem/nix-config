{ config, lib, pkgs, ... }:
let
  cfg = config.packs.gaming;
in {
  options.packs.gaming = {
    enable = lib.mkEnableOption "userland gaming toolchain";

    lutris.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "lutris — Wine game launcher";
    };

    maa.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "MAA — Arknights automation (GUI core + CLI frontend)";
    };

    ww-manager.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "ww-manager — Wuthering Waves launcher";
    };
  };

  config.home.packages =
    lib.optional cfg.lutris.enable pkgs.lutris
    ++ lib.optionals cfg.maa.enable [
      pkgs.maa-assistant-arknights
      pkgs.maa-cli
    ]
    ++ lib.optional cfg.ww-manager.enable pkgs.ww-manager;
}
