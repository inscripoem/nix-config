{ pkgs, ... }:
let
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
in
{
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
}
