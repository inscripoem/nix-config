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

        # Steam's UI is an X11/CEF client. xwayland-satellite runs the
        # whole Xwayland at the smallest output scale, so on an output
        # with niri scale 2 the UI renders at half size. Steam has no
        # per-window DPI handling and cannot rescale a running client,
        # so read the focused output's scale at launch and force it:
        # Steam's documented STEAM_FORCE_DESKTOPUI_SCALING override.
        # Moving the window across outputs needs a Steam restart; games
        # are unaffected because they carry their own resolution.
        package = pkgs.steam.override {
          extraPreBwrapCmds = ''
            # niri sessions only: KWin scales Xwayland itself, and applying
            # a second factor there would double-scale.
            case "''${XDG_CURRENT_DESKTOP:-}" in
              *niri*)
                if [ -z "''${STEAM_FORCE_DESKTOPUI_SCALING:-}" ] && [ -n "''${NIRI_SOCKET:-}" ]; then
                  scale="$(${pkgs.niri-unstable}/bin/niri msg --json focused-output 2>/dev/null \
                    | ${pkgs.jq}/bin/jq -r '.logical.scale // empty' 2>/dev/null || true)"
                  if [ -n "$scale" ]; then
                    export STEAM_FORCE_DESKTOPUI_SCALING="$scale"
                  fi
                fi
                ;;
            esac
          '';
        };

        extraCompatPackages = [
          pkgs.proton-ge-bin
          pkgs.dwproton-bin
        ];
      };
      # steam.run exposes the Steam FHS runtime as `steam-run` for arbitrary
      # unpatched binaries; its closure is shared with programs.steam.
      environment.systemPackages = [
        pkgs.steamcmd
        pkgs.steam.run
      ];
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
