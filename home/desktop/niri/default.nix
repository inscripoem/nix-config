{ pkgs, lib, config, osConfig, ... }:
let
  cfg = config.programs.niri;

  # Append DMS optional includes so Settings pages detect "initialized"
  # and any GUI-changed values in ~/.config/niri/dms/*.kdl take effect.
  # These files are owned by the DMS GUI and NOT managed by this flake:
  # rebuilds neither track nor clobber them, and because the includes land
  # last, they override binds and settings declared above. Consult the
  # live ~/.config/niri/dms/*.kdl files to see what currently takes effect.
  configWithDmsIncludes = pkgs.runCommand "niri-config-validated" {
    nativeBuildInputs = [ cfg.package ];
    passAsFile = [ "configBody" ];
    configBody = cfg.finalConfig + ''

      // DMS-managed overrides (optional — files don't have to exist)
      include optional=true "dms/binds.kdl"
      include optional=true "dms/layout.kdl"
      include optional=true "dms/colors.kdl"
      include optional=true "dms/alttab.kdl"
      include optional=true "dms/outputs.kdl"
      // Named per fragment because DMS settings greps for these exact
      // lines to decide whether a section still needs "First Time Setup".
      include optional=true "dms/input.kdl"
      include optional=true "dms/windowrules.kdl"
      include optional=true "dms/cursor.kdl"
    '';
  } ''
    niri validate -c "$configBodyPath"
    cp "$configBodyPath" $out
  '';

  # State file (under XDG_STATE_HOME) shared by fake-screen-toggle and the
  # session-start restore script below.
  fakeScreenStateFile = "sunshine/fake-screen";

  # Session-start state restore: the niri config pin re-enables the fake
  # output on every login; if the user last toggled it off, disable it
  # again shortly after startup. Referencing osConfig here is safe on
  # non-streaming hosts — the binding is only used under the gated
  # spawn-at-startup entry, and Nix never forces unused bindings.
  fakeScreenInit = pkgs.writeShellScript "fake-screen-init" ''
    fake="${osConfig.modules.capabilities.sunshine.fakeOutputName}"
    state_file="''${XDG_STATE_HOME:-$HOME/.local/state}/${fakeScreenStateFile}"
    [ -f "$state_file" ] || exit 0
    [ "$(cat "$state_file" 2>/dev/null)" = "off" ] || exit 0
    sleep 1
    exec "${cfg.package}/bin/niri" msg output "$fake" off
  '';
in
{
  imports = [
    ./theme-sync.nix
    ./tray-heal.nix
  ];

  programs.niri = {
    settings = {
      binds = {
        # ── User-preserved custom binds ──
        "Ctrl+Alt+T" = {
          hotkey-overlay = { title = "Open a Terminal: wezterm"; };
          action.spawn = "wezterm";
        };
        "Alt+Space" = {
          hotkey-overlay = { title = "Run an Application: dms"; };
          action.spawn = [ "dms" "ipc" "call" "spotlight" "toggle" ];
        };

        # ── Hotkey overlay ──
        "Mod+Shift+Slash".action."show-hotkey-overlay" = [];

        # ── Lock screen ──
        "Super+Alt+L" = {
          hotkey-overlay = { title = "Lock the Screen: swaylock"; };
          action.spawn = "swaylock";
        };

        # ── Audio / Media ──
        "XF86AudioRaiseVolume" = {
          allow-when-locked = true;
          action.spawn = [ "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1+" "-l" "1.0" ];
        };
        "XF86AudioLowerVolume" = {
          allow-when-locked = true;
          action.spawn = [ "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1-" ];
        };
        "XF86AudioMute" = {
          allow-when-locked = true;
          action.spawn = [ "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle" ];
        };
        "XF86AudioMicMute" = {
          allow-when-locked = true;
          action.spawn = [ "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle" ];
        };
        "XF86AudioPlay" = {
          allow-when-locked = true;
          action.spawn = [ "playerctl" "play-pause" ];
        };
        "XF86AudioPause" = {
          allow-when-locked = true;
          action.spawn = [ "playerctl" "play-pause" ];
        };
        "XF86AudioStop" = {
          allow-when-locked = true;
          action.spawn = [ "playerctl" "stop" ];
        };
        "XF86AudioPrev" = {
          allow-when-locked = true;
          action.spawn = [ "playerctl" "previous" ];
        };
        "XF86AudioNext" = {
          allow-when-locked = true;
          action.spawn = [ "playerctl" "next" ];
        };

        # ── Brightness ──
        "XF86MonBrightnessUp" = {
          allow-when-locked = true;
          action.spawn = [ "brightnessctl" "--class=backlight" "set" "+10%" ];
        };
        "XF86MonBrightnessDown" = {
          allow-when-locked = true;
          action.spawn = [ "brightnessctl" "--class=backlight" "set" "10%-" ];
        };

        # ── Overview ──
        "Mod+O" = { repeat = false; action."toggle-overview" = []; };

        # ── Close window ──
        "Mod+Q" = { repeat = false; action."close-window" = []; };

        # ── Arrow keys (focus) ──
        "Mod+Left".action."focus-column-left" = [];
        "Mod+Down".action."focus-window-down" = [];
        "Mod+Up".action."focus-window-up" = [];
        "Mod+Right".action."focus-column-right" = [];

        # ── Vim keys (focus) ──
        "Mod+H".action."focus-column-left" = [];
        "Mod+J".action."focus-window-down" = [];
        "Mod+K".action."focus-window-up" = [];
        "Mod+L".action."focus-column-right" = [];

        # ── Ctrl+arrows (move) ──
        "Mod+Ctrl+Left".action."move-column-left" = [];
        "Mod+Ctrl+Down".action."move-window-down" = [];
        "Mod+Ctrl+Up".action."move-window-up" = [];
        "Mod+Ctrl+Right".action."move-column-right" = [];

        # ── Ctrl+Vim (move) ──
        "Mod+Ctrl+H".action."move-column-left" = [];
        "Mod+Ctrl+J".action."move-window-down" = [];
        "Mod+Ctrl+K".action."move-window-up" = [];
        "Mod+Ctrl+L".action."move-column-right" = [];

        # ── First/last column ──
        "Mod+Home".action."focus-column-first" = [];
        "Mod+End".action."focus-column-last" = [];
        "Mod+Ctrl+Home".action."move-column-to-first" = [];
        "Mod+Ctrl+End".action."move-column-to-last" = [];

        # ── Multi-monitor: focus ──
        "Mod+Shift+Left".action."focus-monitor-left" = [];
        "Mod+Shift+Down".action."focus-monitor-down" = [];
        "Mod+Shift+Up".action."focus-monitor-up" = [];
        "Mod+Shift+Right".action."focus-monitor-right" = [];
        "Mod+Shift+H".action."focus-monitor-left" = [];
        "Mod+Shift+J".action."focus-monitor-down" = [];
        "Mod+Shift+K".action."focus-monitor-up" = [];
        "Mod+Shift+L".action."focus-monitor-right" = [];

        # ── Multi-monitor: move column ──
        "Mod+Shift+Ctrl+Left".action."move-column-to-monitor-left" = [];
        "Mod+Shift+Ctrl+Down".action."move-column-to-monitor-down" = [];
        "Mod+Shift+Ctrl+Up".action."move-column-to-monitor-up" = [];
        "Mod+Shift+Ctrl+Right".action."move-column-to-monitor-right" = [];
        "Mod+Shift+Ctrl+H".action."move-column-to-monitor-left" = [];
        "Mod+Shift+Ctrl+J".action."move-column-to-monitor-down" = [];
        "Mod+Shift+Ctrl+K".action."move-column-to-monitor-up" = [];
        "Mod+Shift+Ctrl+L".action."move-column-to-monitor-right" = [];

        # ── Workspace switching ──
        "Mod+Page_Down".action."focus-workspace-down" = [];
        "Mod+Page_Up".action."focus-workspace-up" = [];
        "Mod+U".action."focus-workspace-down" = [];
        "Mod+I".action."focus-workspace-up" = [];

        "Mod+Ctrl+Page_Down".action."move-column-to-workspace-down" = [];
        "Mod+Ctrl+Page_Up".action."move-column-to-workspace-up" = [];
        "Mod+Ctrl+U".action."move-column-to-workspace-down" = [];
        "Mod+Ctrl+I".action."move-column-to-workspace-up" = [];

        "Mod+Shift+Page_Down".action."move-workspace-down" = [];
        "Mod+Shift+Page_Up".action."move-workspace-up" = [];
        "Mod+Shift+U".action."move-workspace-down" = [];
        "Mod+Shift+I".action."move-workspace-up" = [];

        # ── Scroll wheel ──
        "Mod+WheelScrollDown" = {
          cooldown-ms = 150;
          action."focus-workspace-down" = [];
        };
        "Mod+WheelScrollUp" = {
          cooldown-ms = 150;
          action."focus-workspace-up" = [];
        };
        "Mod+Ctrl+WheelScrollDown" = {
          cooldown-ms = 150;
          action."move-column-to-workspace-down" = [];
        };
        "Mod+Ctrl+WheelScrollUp" = {
          cooldown-ms = 150;
          action."move-column-to-workspace-up" = [];
        };
        "Mod+WheelScrollRight".action."focus-column-right" = [];
        "Mod+WheelScrollLeft".action."focus-column-left" = [];
        "Mod+Ctrl+WheelScrollRight".action."move-column-right" = [];
        "Mod+Ctrl+WheelScrollLeft".action."move-column-left" = [];

        "Mod+Shift+WheelScrollDown".action."focus-column-right" = [];
        "Mod+Shift+WheelScrollUp".action."focus-column-left" = [];
        "Mod+Ctrl+Shift+WheelScrollDown".action."move-column-right" = [];
        "Mod+Ctrl+Shift+WheelScrollUp".action."move-column-left" = [];

        # ── Workspaces 1-9 ──
        "Mod+1".action."focus-workspace" = 1;
        "Mod+2".action."focus-workspace" = 2;
        "Mod+3".action."focus-workspace" = 3;
        "Mod+4".action."focus-workspace" = 4;
        "Mod+5".action."focus-workspace" = 5;
        "Mod+6".action."focus-workspace" = 6;
        "Mod+7".action."focus-workspace" = 7;
        "Mod+8".action."focus-workspace" = 8;
        "Mod+9".action."focus-workspace" = 9;

        "Mod+Ctrl+1".action."move-column-to-workspace" = 1;
        "Mod+Ctrl+2".action."move-column-to-workspace" = 2;
        "Mod+Ctrl+3".action."move-column-to-workspace" = 3;
        "Mod+Ctrl+4".action."move-column-to-workspace" = 4;
        "Mod+Ctrl+5".action."move-column-to-workspace" = 5;
        "Mod+Ctrl+6".action."move-column-to-workspace" = 6;
        "Mod+Ctrl+7".action."move-column-to-workspace" = 7;
        "Mod+Ctrl+8".action."move-column-to-workspace" = 8;
        "Mod+Ctrl+9".action."move-column-to-workspace" = 9;

        # ── Consume/expel columns ──
        "Mod+BracketLeft".action."consume-or-expel-window-left" = [];
        "Mod+BracketRight".action."consume-or-expel-window-right" = [];
        "Mod+Comma".action."consume-window-into-column" = [];
        "Mod+Period".action."expel-window-from-column" = [];

        # ── Preset column widths ──
        "Mod+R".action."switch-preset-column-width" = [];
        "Mod+Shift+R".action."switch-preset-column-width-back" = [];
        "Mod+Ctrl+Shift+R".action."switch-preset-window-height" = [];
        "Mod+Ctrl+R".action."reset-window-height" = [];

        # ── Maximize / Fullscreen / Center ──
        "Mod+M".action."maximize-window-to-edges" = [];
        "Mod+F".action."maximize-column" = [];
        "Mod+Shift+F".action."fullscreen-window" = [];
        "Mod+Ctrl+F".action."expand-column-to-available-width" = [];
        "Mod+C".action."center-column" = [];
        "Mod+Ctrl+C".action."center-visible-columns" = [];

        # ── Fine width/height adjustments ──
        "Mod+Minus".action."set-column-width" = "-10%";
        "Mod+Equal".action."set-column-width" = "+10%";
        "Mod+Shift+Minus".action."set-window-height" = "-10%";
        "Mod+Shift+Equal".action."set-window-height" = "+10%";

        # ── Floating windows ──
        "Mod+V".action."toggle-window-floating" = [];
        "Mod+Shift+V".action."switch-focus-between-floating-and-tiling" = [];

        # ── Tabbed display ──
        "Mod+W".action."toggle-column-tabbed-display" = [];

        # ── Screenshots ──
        "Print".action.screenshot = [];
        "Ctrl+Print".action."screenshot-screen" = [];
        "Alt+Print".action."screenshot-window" = [];

        # ── Keyboard shortcut inhibitor escape hatch ──
        "Mod+Escape" = {
          allow-inhibiting = false;
          action."toggle-keyboard-shortcuts-inhibit" = [];
        };

        # ── Quit / Power off ──
        "Mod+Shift+E".action.quit = [];
        "Ctrl+Alt+Delete".action.quit = [];
        "Mod+Shift+P".action."power-off-monitors" = [];
      };

      spawn-at-startup = lib.mkAfter (lib.optionals osConfig.modules.capabilities.sunshine.enable [
        # Restore the persisted fake-output on/off state after login (the
        # config pin above re-enables the fake output on every session
        # start); see fakeScreenInit in the let block.
        { command = [ "${fakeScreenInit}" ]; }
      ]);

      xwayland-satellite = {
        path = "${pkgs.xwayland-satellite}/bin/xwayland-satellite";
      };

      prefer-no-csd = true;

      # Clicking a notification action only sends D-Bus ActionInvoked; the app
      # self-activates via xdg-activation with a serial-less token, which niri
      # by default degrades to an urgent-only flash (nothing in the shell chain
      # can focus the window: quickshell NotificationAction.invoke just emits
      # the signal — dux-shell #533). Honor such tokens so notification clicks
      # bring the app forward.
      debug = {
        "honor-xdg-activation-with-invalid-serial" = [ ];
      };

      environment = {
        "NIXOS_OZONE_WL" = "1";
        "XDG_CURRENT_DESKTOP" = "niri";
        "XDG_SESSION_TYPE" = "wayland";
        "XDG_SESSION_DESKTOP" = "niri";
        # Qt theming: plain "gtk3", NOT "xdgdesktopportal:gtk3". The portal
        # variant resolves the icon theme through the portal (breeze /
        # breeze-dark, maintained by DMS), and those themes carry neither
        # input-keyboard-symbolic nor any fcitx icons — DMS's tray then fails
        # to load fcitx5's icon (quickshell shows its magenta checkerboard
        # placeholder; fcitx-rime renders inverted). Dark-mode flips from
        # kded6 are blocked at the source by the gtkconfig autoload=false in
        # kded6rc below. theme-sync mirrors this into the systemd user
        # manager environment so apps launched through Dolphin's
        # app-services inherit it too.
        "QT_QPA_PLATFORMTHEME" = "gtk3";
      };

      # Fake streaming output (kernel-forced EDID, hosts with the Sunshine
      # capability — see modules/nixos/capabilities/sunshine.nix). Pinned
      # to the SAME mode the real monitor runs (1080p@60) so the two
      # screens are logically identical: disabling the fake output makes
      # niri migrate its workspaces onto the real monitor untouched, and
      # fake-screen-toggle moves them back when going remote — the desk
      # screen and the streamed picture are the same desktop. The EDID
      # retains its 4K preferred timing, so a future 4K or scale-2 canvas
      # is a pin change, not an EDID rebuild. Gated on the capability and
      # named from its option, so non-streaming desktops carry none of
      # this — even if their real monitor happens to sit on a connector
      # with the same name. DMS's GUI-managed include dms/outputs.kdl
      # lands last and wins if the user manages this output through the
      # DMS display settings.
      outputs = lib.mkIf osConfig.modules.capabilities.sunshine.enable {
        "${osConfig.modules.capabilities.sunshine.fakeOutputName}" = {
          mode = {
            width = 1920;
            height = 1080;
            refresh = 60.0;
          };
        };
      };

    };
  };

  # Session handover button between the real monitor and the fake
  # streaming output. niri's JSON output list only contains enabled
  # outputs, so its presence is the on/off signal:
  #   OFF (back at the desk): disable the fake output — niri migrates its
  #   workspaces to the remaining output automatically.
  #   ON (going remote): enable the fake output, then move every
  #   workspace from the real monitor over, so Moonlight picks up exactly
  #   what was on the desk screen.
  # The last state is recorded so the init script (let binding below) can
  # restore "off" after a relogin — the config pin re-enables the output
  # on every session start. Gated on the Sunshine capability.
  home.packages = lib.mkIf osConfig.modules.capabilities.sunshine.enable [
    (pkgs.writeShellScriptBin "fake-screen-toggle" ''
      fake="${osConfig.modules.capabilities.sunshine.fakeOutputName}"
      state_file="''${XDG_STATE_HOME:-$HOME/.local/state}/${fakeScreenStateFile}"
      niri="${cfg.package}/bin/niri"

      outputs=$("$niri" msg --json outputs 2>/dev/null) || outputs='{}'
      if printf '%s' "$outputs" | ${pkgs.jq}/bin/jq -e --arg fake "$fake" 'has($fake)' >/dev/null 2>&1; then
        "$niri" msg output "$fake" off
        state=off
      else
        "$niri" msg output "$fake" on
        # Workspaces are moved by stable id; niri always keeps at least
        # one (empty) workspace per output, so the desk screen is not
        # left output-less.
        "$niri" msg --json workspaces 2>/dev/null \
          | ${pkgs.jq}/bin/jq -r --arg fake "$fake" '.[] | select(.output != $fake) | .id' \
          | while IFS= read -r ws; do
              "$niri" msg action move-workspace-to-monitor --reference "$ws" "$fake"
            done
        state=on
      fi
      mkdir -p "$(dirname "$state_file")"
      printf '%s\n' "$state" > "$state_file"
    '')
  ];

  # Override config file source to append DMS optional includes.
  xdg.configFile.niri-config = lib.mkForce {
    enable = true;
    target = "niri/config.kdl";
    source = configWithDmsIncludes;
  };

  # kded6's gtkconfig module syncs the (light) kdeglobals palette into
  # ~/.config/gtk-{3,4}.0/settings.ini — including
  # gtk-application-prefer-dark-theme=false — every time a KDE app activates
  # kded6 (e.g. opening a file from Dolphin), clobbering the value theme-sync
  # maintains from DMS's color-scheme. DMS owns that key in this session, so
  # stop the module from loading at all. The KDE fallback session keeps its
  # plasma-manager theming; only its KDE→GTK auto-sync is lost. force because
  # KDE apps may rewrite kded6rc at runtime; this setting must survive
  # switches.
  #
  # statusnotifierwatcher: kded6 autoloads this plasma-workspace module, and
  # its watcher claims org.kde.StatusNotifierWatcher whenever the name sits
  # free for a few seconds. dms.service is Type=dbus with that exact BusName,
  # so a hijack turns every dms start into a 90s start-job timeout and
  # Restart=on-failure loops it forever. Seen live 2026-10-30: a dms restart
  # whose stop phase burned the whole TimeoutStopSec left the name free ~90s,
  # kded6 claimed it within ~2s, and every manual recovery lost the race
  # (kded6 respawns in 2-3s, dms needs ~10s to reach the claim). The module's
  # X-KDE-Kded-load-on-demand is false, so blocking autoload blocks every
  # load path. Plasma sessions keep working: plasmashell owns the watcher
  # name there on its own.
  xdg.configFile."kded6rc" = {
    force = true;
    text = ''
      [Module-gtkconfig]
      autoload=false

      [Module-statusnotifierwatcher]
      autoload=false
    '';
  };

  # DMS as a systemd user service — DMS's documented deployment mode —
  # scoped to niri: WantedBy=niri.service instead of the upstream module's
  # graphical-session.target binding, which would also start the shell
  # under the KDE fallback session (see modules/nixos/desktop/dms-shell.nix
  # for why that matters). Type=dbus holds the unit un-started until the
  # StatusNotifierWatcher name is owned; combined with the autostart
  # template drop-in below this gives XDG autostart apps a hard barrier:
  # Electron tray items are registered exactly once, at creation, so those
  # apps must never start before the watcher exists (that boot race — lost
  # by 3.4s on 2026-10-23 — is what cost the 1Password/WorkBuddy tray
  # icons until the app was restarted into a live watcher).
  systemd.user.services.dms = {
    Unit = {
      Description = "DankMaterialShell desktop shell (niri sessions)";
      After = [ "niri.service" "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "niri.service" ];
    Service = {
      Type = "dbus";
      BusName = "org.kde.StatusNotifierWatcher";
      ExecStart = "${pkgs.dux-shell}/bin/dms run --session";
      Restart = "on-failure";
      RestartSec = "2s";
    };
  };

  # XDG autostart applications wait for the shell. The drop-in targets the
  # systemd-xdg-autostart-generator's TEMPLATE unit, not
  # xdg-desktop-autostart.target: the target only Wants= the generated
  # app-*@autostart.service units, and Wants pulls units in without
  # ordering them, so an After=dms.service on the target never reached
  # them (verified 2026-10-23: 1Password/WorkBuddy started 27ms before
  # dms.service and missed the watcher by 3.4s). A drop-in on
  # app-@autostart.service applies to every instance — escaped names
  # included — and orders each app strictly after dms.service is started,
  # which for Type=dbus means the StatusNotifierWatcher name is owned.
  # In KDE fallback sessions dms.service is never pulled into the boot
  # transaction, so the After= stays inert and autostart proceeds.
  xdg.configFile."systemd/user/app-@autostart.service.d/10-order-after-dms.conf".text = ''
    [Unit]
    After=dms.service
  '';
}
