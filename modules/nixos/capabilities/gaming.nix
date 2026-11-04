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
        # with niri scale 2 the UI renders at half size. This client
        # ignores STEAM_FORCE_DESKTOPUI_SCALING, and its Chromium switches
        # never reach the UI process; the knob that works is
        # Accessibility/DesktopUIScale in config.vdf (the Settings >
        # Accessibility slider), read at client startup. Rewrite it
        # before a fresh launch from the focused output's scale. The
        # setting's range is 0.5-2.0, so a future output above 2.0 is
        # clamped there. Steam cannot rescale a running client, so
        # moving the window across outputs needs a restart; games are
        # unaffected. The slider is wrapper-managed in niri sessions.
        package = pkgs.steam.override {
          extraPreBwrapCmds = ''
            # niri sessions only: KWin scales Xwayland itself, and applying
            # a second factor there would double-scale.
            case "''${XDG_CURRENT_DESKTOP:-}" in
              *niri*)
                if [ -n "''${NIRI_SOCKET:-}" ] && ! ${pkgs.procps}/bin/pgrep -x steam >/dev/null 2>&1; then
                  scale="$(${pkgs.niri-unstable}/bin/niri msg --json focused-output 2>/dev/null \
                    | ${pkgs.jq}/bin/jq -r '.logical.scale // empty | if . < 0.5 then 0.5 elif . > 2 then 2 else . end' 2>/dev/null || true)"
                  cfg="$HOME/.local/share/Steam/config/config.vdf"
                  if [ -n "$scale" ] && [ -f "$cfg" ] \
                    && ${pkgs.gnugrep}/bin/grep -q '"DesktopUIScale"' "$cfg" \
                    && ! ${pkgs.gnugrep}/bin/grep -qE "\"DesktopUIScale\"[[:space:]]*\"$scale\"" "$cfg"; then
                    tmp="$(${pkgs.coreutils}/bin/mktemp "$cfg.XXXXXX")"
                    ${pkgs.coreutils}/bin/cp -p "$cfg" "$tmp"
                    ${pkgs.gnused}/bin/sed -i 's/\("DesktopUIScale"[[:space:]]*"\)[^"]*"/\1'"$scale"'"/' "$tmp"
                    ${pkgs.coreutils}/bin/mv "$tmp" "$cfg"
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
