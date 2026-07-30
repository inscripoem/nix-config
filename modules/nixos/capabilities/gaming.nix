{ config, lib, pkgs, ... }:
let
  cfg = config.modules.capabilities.gaming;
in {
  options.modules.capabilities.gaming = {
    enable = lib.mkEnableOption "gaming system integration (Steam, gamemode, Waydroid)";

    steam.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Steam + Proton-GE + Arknights: Endfield ACE-patched proton";
    };

    gamemode.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Feral Interactive gamemode daemon";
    };

    aagl = {
      anime-game-launcher.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Genshin Impact launcher (AAGL)";
      };
      honkers-railway-launcher.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Honkai: Star Rail launcher (AAGL)";
      };
      sleepy-launcher.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Zenless Zone Zero launcher (AAGL)";
      };
    };

    waydroid = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Waydroid Android container (Arknights + MAA)";
      };
      helper.enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.waydroid.enable;
        description = "waydroid-helper GUI + android-tools (adb/fastboot) for driving Waydroid";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.steam.enable {
      programs.steam = {
        enable = true;
        extraCompatPackages = [
          pkgs.proton-ge-bin
          pkgs.dwproton-bin
        ];
      };
    })

    (lib.mkIf cfg.gamemode.enable {
      programs.gamemode.enable = true;
    })

    (lib.mkIf cfg.aagl.anime-game-launcher.enable {
      programs.anime-game-launcher.enable = true;
    })

    (lib.mkIf cfg.aagl.honkers-railway-launcher.enable {
      programs.honkers-railway-launcher.enable = true;
    })

    (lib.mkIf cfg.aagl.sleepy-launcher.enable {
      programs.sleepy-launcher.enable = true;
    })

    (lib.mkIf cfg.waydroid.enable {
      virtualisation.waydroid.enable = true;
      virtualisation.waydroid.package = pkgs.waydroid-nftables;
    })

    (lib.mkIf cfg.waydroid.helper.enable {
      environment.systemPackages = [
        pkgs.waydroid-helper
        pkgs.android-tools
      ];
    })
  ];
}
