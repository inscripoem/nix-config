{ pkgs, lib, config, ... }:
let
  cfg = config.programs.niri;

  # DMS only syncs the portal `color-scheme` signal, never the legacy GTK
  # `gtk-application-prefer-dark-theme` key. Electron apps (notion) decide
  # light/dark from that GTK key, so keep it in lockstep with DMS's theme.
  # DMS itself never re-reads the icon theme at runtime (Qt gtk3 platform
  # theme only loads settings.ini at startup, and the tray IconImage caches by
  # URL), so we also restart DMS on theme switch to pick up the new icon
  # theme for Qt-rendered tray icons (fcitx5 etc.).
  # DMS also never APPLIES the per-mode icon theme at startup: it writes
  # gtk-icon-theme-name only during an explicit mode switch, and that async
  # detached write races this script's own sed on the same file (plus
  # restart_dms kills DMS ~1s after the flip), so a lost write strands the
  # previous session's theme in settings.ini — after which every fresh boot
  # renders light-mode tray icons (breeze's dark fcitx-rime glyph) in a dark
  # session. Mirror the icon theme here from DMS's own settings.json so boot
  # state is deterministic; on a flip both writers now target the same value,
  # defusing the clobber.
  # Third writer on these keys: any KDE app can load kded6's gtkconfig module
  # on demand (autoload=false in kded6rc only blocks kded6's own autostart),
  # and that load mirrors the light plasma-manager kdeglobals into
  # settings.ini without touching the portal, so the monitor loop gets no
  # event; a poll sentinel below repairs such drift, with the portal value
  # as the single source of truth.
  # NOTE: name must NOT contain "gtk" — DMS runs `pkill -HUP -f gtk` on every
  # theme switch (intended to reload GTK apps), which would kill this script.
  themeSync = pkgs.writeShellScript "theme-sync" ''
    # Re-import the authoritative user PATH from the systemd user manager
    # (PAM + ~/.config/environment.d merged). Hardcoding would starve dms,
    # which resolves relative Exec= command names from .desktop files
    # against its own PATH. Pulling systemd's PATH keeps every profile dir
    # (home-manager, nix-profile, flatpak, ...) in sync automatically.
    PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^PATH=//p')
    [ -n "$PATH" ] || PATH=/run/current-system/sw/bin:/usr/bin:/bin
    export PATH

    # gdbus must not depend on PATH: no system or user profile on this
    # machine carries it, and when the user profile that once did was
    # cleaned up, every gdbus call/monitor below started failing silently
    # (their stderr is discarded): the portal read in sync_prefer_dark
    # always returned failure, so the boot-seed DMS restart, the drift
    # sentinel and the mode-switch monitor all died and mode switches
    # stopped reaching restart_dms. Pin the store path so PATH churn can
    # never strand this logic again.
    gdbus() { "${pkgs.glib}/bin/gdbus" "$@"; }

    # Single-instance sweep. This script has no Wayland connection, so it
    # outlives the niri session that spawned it (logout does not reap its
    # transient scope); without this, each relogin leaks another monitor and
    # one theme switch relaunches dms once per monitor — the double status
    # bar. comm is useless here (bash 5.3 sets it to the first 15 chars of
    # the script filename for store-path shebangs, plain "bash" for env-bash
    # launches), so match the script path at the end of the command line and
    # confirm argv: the interpreter must end in bash and this script must be
    # the last argument — that still excludes editors or tails that merely
    # mention the path.
    # Suffix match on purpose: it also catches instances still running under
    # the script's old name ("dark-theme-sync"), so the first rebuild+relogin
    # after a rename sweeps them too.
    for pid in $(pgrep -f 'theme-sync$'); do
      [ "$pid" = "$$" ] && continue
      first=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | head -n1)
      last=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | sed '/^$/d' | tail -n1)
      [ -n "$first" ] || continue
      [[ $first = *bash && $last = *theme-sync ]] || continue
      pkill -TERM -P "$pid" 2>/dev/null
      kill "$pid" 2>/dev/null
    done

    # Niri-only Qt theme bridge. niri's `environment` block only reaches
    # processes niri spawns itself; apps launched through the systemd user
    # manager (Dolphin -> app-org.kde.*.service) never see it and fall back to
    # the light kdeglobals palette. Mirror our own value into the manager and
    # dbus activation environments so those apps resolve through the same GTK
    # settings this script keeps in lockstep with DMS's color-scheme — follows
    # light exactly as it follows dark, nothing here hardcodes a mode. A
    # watcher unsets it when niri dies so a KDE fallback session never
    # inherits it.
    if [ -n "$QT_QPA_PLATFORMTHEME" ]; then
      systemctl --user set-environment "QT_QPA_PLATFORMTHEME=$QT_QPA_PLATFORMTHEME"
      dbus-update-activation-environment --systemd QT_QPA_PLATFORMTHEME 2>/dev/null
      # Sandbox apps (e.g. the Baidu Netdisk flatpak) ask the portal to spawn
      # host apps, and those children inherit the portal daemon's own
      # environment. The portal usually starts before we do, so restart it
      # once here to make sure it carries the mirrored variable.
      systemctl --user try-restart xdg-desktop-portal.service 2>/dev/null
    fi
    # The script itself is reparented to the systemd user manager (niri wraps
    # spawn-at-startup in transient scopes), so $PPID cannot detect session
    # death — poll for the compositor process instead.
    ( while pgrep -x niri >/dev/null 2>&1; do sleep 5; done
      systemctl --user unset-environment QT_QPA_PLATFORMTHEME 2>/dev/null
      dbus-update-activation-environment --systemd --unset QT_QPA_PLATFORMTHEME 2>/dev/null ) &

    # Resolve the icon theme exactly like DMS's SettingsData.resolveIconTheme:
    # the per-mode light slot only when iconThemePerMode is on and the mode is
    # light, otherwise the dark slot. "System Default" (or a missing key)
    # means DMS manages nothing — leave settings.ini alone in that case.
    # $1 = "true" when the resolved mode is prefer-dark.
    desired_icon_theme() {
      local sj="$HOME/.config/DankMaterialShell/settings.json"
      [ -f "$sj" ] || return 0
      local per_mode dark light icon
      per_mode=$(sed -nE 's/.*"iconThemePerMode": *(true|false).*/\1/p' "$sj" | head -n1)
      dark=$(sed -nE 's/.*"iconThemeDark": *"([^"]*)".*/\1/p' "$sj" | head -n1)
      light=$(sed -nE 's/.*"iconThemeLight": *"([^"]*)".*/\1/p' "$sj" | head -n1)
      if [ "$per_mode" = true ] && [ "$1" = false ]; then icon=$light; else icon=$dark; fi
      case "$icon" in
        ""|"System Default") return 0 ;;
      esac
      printf '%s' "$icon"
    }

    sync_prefer_dark() {
      local scheme cur
      scheme=$(gdbus call --session \
        --dest org.freedesktop.portal.Desktop \
        --object-path /org/freedesktop/portal/desktop \
        --method org.freedesktop.portal.Settings.Read \
        "org.freedesktop.appearance" "color-scheme" 2>/dev/null \
        | sed -n 's/.*uint32 \([0-9]*\).*/\1/p')
      [ -n "$scheme" ] || return 1   # portal read failed: leave last_val alone
      icon_changed=false
      local val=false changed=true
      [ "$scheme" = "1" ] && val=true   # 1 = prefer dark
      local icon
      icon=$(desired_icon_theme "$val")
      for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
        [ -f "$f" ] || continue
        # Drift-gated write: the sentinel calls this every few seconds, and an
        # unconditional sed would churn mtime and re-arm the lost-write race
        # against DMS's own detached settings.ini writes.
        cur=$(sed -n 's/^gtk-application-prefer-dark-theme=//p' "$f" | head -n1)
        if [ "$cur" != "$val" ]; then
          if grep -q '^gtk-application-prefer-dark-theme=' "$f"; then
            sed -i "s|^gtk-application-prefer-dark-theme=.*|gtk-application-prefer-dark-theme=$val|" "$f"
          else
            printf 'gtk-application-prefer-dark-theme=%s\n' "$val" >> "$f"
          fi
        fi
        [ -n "$icon" ] || continue
        if grep -q '^gtk-icon-theme-name=' "$f"; then
          if [ "$(sed -n 's/^gtk-icon-theme-name=//p' "$f" | head -n1)" != "$icon" ]; then
            sed -i "s|^gtk-icon-theme-name=.*|gtk-icon-theme-name=$icon|" "$f"
            icon_changed=true
          fi
        elif grep -q '^\[Settings\]' "$f"; then
          sed -i '/^\[Settings\]/a gtk-icon-theme-name='"$icon" "$f"
          icon_changed=true
        fi
      done
      # Portal clients poke Settings.Read without changing anything (e.g.
      # 1Password unlock) and gdbus monitor still emits an event; restarting
      # dms on those just blanks the bar. Return 0 only when the scheme
      # actually flipped so the caller restarts then. (icon_changed is
      # detected on disk instead: a boot-time stale key must restart DMS even
      # though the scheme did not flip.)
      [ "$val" = "$last_val" ] && changed=false
      last_val=$val
      [ "$changed" = true ]
    }
    last_val=""
    icon_changed=false

    # Restart DMS so its Qt process re-reads the icon theme. DMS runs as the
    # dms.service user unit (declared below), so a unit restart is clean by
    # construction — no process matching, and the old pkill-by-cmdline dance
    # (needed to spare the in-flight `dms matugen queue` theme worker from
    # SIGTERM) is unnecessary now that systemd only restarts the unit's own
    # cgroup.
    restart_dms() {
      systemctl --user restart dms.service
      # A watcher restart drops every registration it held. fcitx5 re-registers
      # on its own; tray-heal replays the rest on the apps' behalf — both
      # well-known SNI names (sunshine etc.) and Electron items found by
      # probing unique bus names for a live /StatusNotifierItem object.
      ${trayHeal} >/dev/null 2>&1 &
    }

    # Boot seed: sync both keys once. DMS read the icon theme while starting,
    # so if that key was stale (a write lost to the flip race in a previous
    # session) restart DMS once to re-resolve tray icons through the corrected
    # theme. Scheme flips below keep the last_val semantics. The if-form keeps
    # sync_prefer_dark's nonzero returns out of any set -e discussion.
    if sync_prefer_dark && [ "$icon_changed" = true ]; then restart_dms; fi

    # Drift sentinel. kded6's gtkconfig module can be loaded on demand by any
    # KDE app (autoload=false only blocks kded6's own startup load), and each
    # load mirrors plasma-manager's light kdeglobals into settings.ini —
    # including prefer-dark=false and the icon key — without touching the
    # portal, so the monitor loop gets no event to retaliate with. Repair via
    # sync_prefer_dark: its drift-gated writes keep a clean tick free of disk
    # traffic, and no DMS restart here — DMS resolved its icon theme at
    # startup and a restored ini does not change it; Qt windows already open
    # keep the polluted palette until relaunched (the gtk3 platform theme
    # reads the key at startup only).
    (
      while sleep 2; do
        sync_prefer_dark
      done
    ) &

    gdbus monitor --session \
      --dest org.freedesktop.portal.Desktop \
      --object-path /org/freedesktop/portal/desktop \
      | while IFS= read -r line; do
          case "$line" in
            *color-scheme*) sync_prefer_dark && restart_dms ;;
          esac
        done
  '';


  # Append DMS optional includes so Settings pages detect "initialized"
  # and any GUI-changed values in ~/.config/niri/dms/*.kdl take effect.
  # These files are owned by the DMS GUI and NOT managed by this flake:
  # rebuilds neither track nor clobber them, and because the includes land
  # last, they override binds and settings declared above. Consult the
  # live ~/.config/niri/dms/*.kdl files to see what currently takes effect.
  # Re-register StatusNotifierItems that are alive on the bus but missing
  # from the watcher's list — they registered before a watcher existed or
  # across a DMS restart. RegisterStatusNotifierItem takes the item's bus
  # name as its argument and quickshell honors that name regardless of
  # caller, so the registration can be replayed on the app's behalf without
  # restarting it (mechanism verified on quickshell 0.3.x upstream:
  # omacom/omarchy#12214; replaying an already-registered item is a no-op).
  # Discovery covers both item styles: well-known
  # org.{kde,freedesktop}.StatusNotifierItem-* names (libappindicator/Qt
  # apps such as sunshine) are listed by name, while Electron items export
  # /StatusNotifierItem on their unique bus names and are found by probing
  # every unique name for the object.
  trayHeal = pkgs.writeShellScript "tray-heal" ''
    PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^PATH=//p')
    [ -n "$PATH" ] || PATH=/run/current-system/sw/bin:/usr/bin:/bin
    export PATH

    watcher_up() {
      busctl --user call org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
        org.freedesktop.DBus.Properties Get ss \
        org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems >/dev/null 2>&1
    }

    registered_items() {
      busctl --user call org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
        org.freedesktop.DBus.Properties Get ss \
        org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems 2>/dev/null \
        | grep -oE '"[^"]*/StatusNotifierItem"' | tr -d '"'
    }

    # theme-sync invokes us right after a dms.service restart, so the
    # watcher is usually back within a couple of seconds. Bail quietly if
    # it never appears: without a watcher there is nothing to repair
    # against (and the Type=dbus barrier covers the autostart path).
    i=0
    until watcher_up; do
      i=$((i + 1))
      if [ "$i" -ge 30 ]; then
        echo "tray-heal: StatusNotifierWatcher never appeared, nothing to do"
        exit 0
      fi
      sleep 2
    done

    reg="$(registered_items)"
    busctl --user list --no-legend --no-pager 2>/dev/null \
      | awk '{print $1}' \
      | while IFS= read -r name; do
          case "$reg" in
            *"$name/StatusNotifierItem"*) continue ;;
          esac
          case "$name" in
            org.kde.StatusNotifierItem-*|org.freedesktop.StatusNotifierItem-*)
              # Well-known item name: ownership is itself the marker.
              ;;
            :1.*)
              # Electron item style: the object lives on a unique bus name,
              # always at the SNI-defined path /StatusNotifierItem. Probe by
              # enumerating the connection's root children. Notes from live
              # testing (2026-10-23): deep-object Introspect is useless —
              # even live Electron items answer it with an empty <node/>,
              # identical to absent ones; and several sandboxed connections
              # never answer Introspect at all, each stalling for busctl's
              # 25s default (--timeout= does not apply to introspect), so the
              # probe must wear an external timeout. Worst case ~15s total;
              # this is a background oneshot, not a boot gate.
              timeout 1 busctl --user introspect --xml "$name" / 2>/dev/null \
                | grep -q 'node name="StatusNotifierItem"' || continue
              ;;
            *) continue ;;
          esac
          echo "tray-heal: re-registering lost tray item $name"
          busctl --user call org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
            org.kde.StatusNotifierWatcher RegisterStatusNotifierItem s "$name" >/dev/null 2>&1 \
            || echo "tray-heal: failed to re-register $name" >&2
        done
  '';

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
    '';
  } ''
    niri validate -c "$configBodyPath"
    cp "$configBodyPath" $out
  '';
in
{
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

      spawn-at-startup = [
        # Keep GTK's legacy dark-theme key in sync with DMS theme mode so
        # Electron tray icons (notion) pick the right icon. DMS itself runs
        # as the dms.service user unit declared below — spawning it here too
        # would race the service for the StatusNotifierWatcher bus name.
        { command = [ "${themeSync}" ]; }
      ];

      xwayland-satellite = {
        path = "${pkgs.xwayland-satellite}/bin/xwayland-satellite";
      };

      prefer-no-csd = true;

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

    };
  };

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
  xdg.configFile."kded6rc" = {
    force = true;
    text = ''
      [Module-gtkconfig]
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

  # Recover tray items whose registration was lost because they came up
  # before the watcher or across a DMS restart (see trayHeal above). Also
  # invoked by theme-sync after every restart_dms.
  systemd.user.services.tray-heal = {
    Unit = {
      Description = "Re-register StatusNotifierItems lost across a watcher restart";
      After = [ "dms.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "niri.service" ];
    Service = {
      Type = "oneshot";
      ExecStart = "${trayHeal}";
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
