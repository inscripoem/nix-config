# Hermes — Apollo-derived self-hosted game-stream host for Moonlight,
# Artemis and Hestia. Replaced Sunshine on 2026-11-11 after the pilot
# recorded in docs/remote-desktop.md. The old capability module
# (capabilities/sunshine.nix) was deleted rather than kept behind a
# runtime switch: rollback is `git revert` + `nhs switch`, since
# ~/.config/sunshine (old state) and ~/.config/hermes (current state)
# are independent directories and the first Hermes start had already
# seeded the pairing certificate from the Sunshine one.
#
# Why Hermes won:
#   - Bidirectional text clipboard sync with Artemis-family clients rides
#     the Apollo control-stream extension; the host side shells out to
#     wl-copy / wl-paste (system wl-clipboard below), so it needs nothing
#     from the compositor beyond niri's wlr data-control protocol.
#   - VBR with single-frame VBV and the zero-copy GBM/dmabuf capture path
#     produced a visibly cleaner picture than the Sunshine wlr setup at
#     the same codec and bitrate (H.264 VAAPI on the WX 5100).
#   - Sunshine-lineage protocol and ports: existing clients reconnected
#     without re-pairing; only newly paired clients change behavior (see
#     the permission warning below).
#   The host-side alternatives comparison from the Sunshine era still
#   holds (KRDP: Wayland-only, no NixOS host path; RustDesk: no NixOS
#   host module, unattended needs a setuid hack; Parsec: no Linux host;
#   krfb: CPU-only, too laggy for HK<->SZ). Full rationale and history:
#   docs/remote-desktop.md.
#
# What this module deliberately drops with Sunshine, and why:
#   - The fake-output machinery (kernel EDID injection, connector pinning,
#     stream-mode/desk-mode handover): retired when the WX 5100 profile
#     switched to the physical monitor. Hermes-KMS could reintroduce
#     per-client virtual displays later as a separate project.
#   - `hermes --prelogin` (built-in pre-login streaming): nightly-only
#     upstream and only ever exercised on KDE+SDDM; the greeter/user
#     handoff below stays until it is proven for greetd+niri.
#   - KWIN_USE_OVERLAYS: was a kmsgrab/KWin workaround, irrelevant to
#     niri's wlr capture path.
#
# How streaming runs before login (Windows-RDP-like experience):
#   Two systemd services cooperate (architecture carried over from the
#   Sunshine module):
#     1. hermes-greeter (system, root) — starts after display-manager and
#        captures the greetd/Dux Greeter session. Artemis/Moonlight
#        connect and see the login screen.
#     2. hermes (user) — starts with graphical-session.target on login.
#        ExecStartPre stops hermes-greeter; ExecStopPost restarts it on
#        logout so the greeter is streamable for the next remote login.
#   This avoids auto-login (which breaks KWallet/gnome-keyring because
#   PAM never sees a password). Both services point HOME at the user's
#   home so the pairing certificate and web-UI credentials are shared:
#   same UUID + certificate means clients see a single host regardless of
#   which service is currently streaming.
#
# Permission system warning (cost a debugging session 2026-11-11):
#   The FIRST client ever paired receives full permissions; every later
#   pairing defaults to View Streams + List Apps only — no mouse,
#   keyboard, launch, or clipboard permissions. The symptom looks like a
#   broken stream (frozen picture, dead input) but is purely permissions:
#   no input -> no desktop damage -> damage-driven capture emits no
#   frames. Grant per client in the web UI (Clients page), or patch the
#   `perm` field in ~/.config/hermes/hermes_state.json while Hermes is
#   stopped — the running process rewrites that file on exit.
#
# Clipboard: text only, 64 KiB cap, via wl-copy / wl-paste on Wayland
# (xclip on X11). wl-clipboard ships system-wide below so the user
# service finds it on the default PATH; niri provides the wlr
# data-control protocol the helpers talk to.

{
  config,
  lib,
  pkgs,
  vars,
  ...
}:
let
  cfg = config.modules.capabilities.hermes;
  hermes = pkgs.hermes;

  # The greeter runs as root outside any user session: with
  # greeterWaylandUser set it waits for that session's Wayland socket and
  # captures it with wlr-screencopy (KMS capture hits EGL_BAD_MATCH when
  # importing the root capture frame on this host); without it, root KMS
  # capture is the fallback (root's default capability set suffices — no
  # setcap wrapper, unlike Sunshine which needed one for the *user*
  # service's KMS path).
  greeterCapture = if cfg.greeterWaylandUser == null then "kms" else "wlr";

  # Declarative settings, passed explicitly to both services so the web UI
  # stays out of the configuration path. The greeter adds a capture
  # override (it cannot inherit the user session's wlr socket) and, after
  # probing, the connector name. `virtual_display_backend = none` streams
  # the session's own output — no EVDI or Hermes-KMS driver involved; the
  # capability is independent of those backends. Sunlight-era `vk_tune`
  # is gone: Hermes does not recognize the key.
  hermesSettings = {
    capture = "wlr";
    virtual_display_backend = "none";
  };
  hermesConfigFile =
    (pkgs.formats.keyValue { }).generate "hermes.conf" hermesSettings;

  # HOME points at the user's home (not root's) so the greeter shares the
  # user service's pairing certificate — see the header.
  #
  # The connector probe mirrors niri's automatic placement (alphabetically
  # first connected output hosts the greeter UI), so the greeter streams
  # the output that actually carries the login screen. An unmatched or
  # empty probe degrades to Hermes' first-monitor default with a journal
  # warning, never a hard failure.
  hermesGreeterWrapper = pkgs.writeShellScript "hermes-greeter" ''
    set -eu
    export HOME="/home/${vars.username}"
    export XDG_CONFIG_HOME="$HOME/.config"

    ${lib.optionalString (cfg.greeterWaylandUser != null) ''
      greeter_uid="$(${pkgs.coreutils}/bin/id -u ${lib.escapeShellArg cfg.greeterWaylandUser})"
      runtime_dir="/run/user/$greeter_uid"
      wayland_display=""
      deadline=$((SECONDS + 180))
      while (( SECONDS < deadline )); do
        for candidate in "$runtime_dir"/wayland-*; do
          [ -S "$candidate" ] || continue
          wayland_display="''${candidate##*/}"
          break
        done
        [ -n "$wayland_display" ] && break
        ${pkgs.coreutils}/bin/sleep 0.2
      done
      if [ -z "$wayland_display" ]; then
        echo "hermes-greeter: greeter Wayland socket did not appear under $runtime_dir" >&2
        exit 1
      fi
      export XDG_RUNTIME_DIR="$runtime_dir"
      export WAYLAND_DISPLAY="$wayland_display"
      export XDG_SESSION_TYPE="wayland"
    ''}

    real="$(for c in /sys/class/drm/card*-*; do
      [ "$(cat "$c/status" 2>/dev/null)" = connected ] || continue
      name="''${c##*/}"
      echo "''${name#*-}"
      break
    done)"

    if [ -n "$real" ]; then
      exec ${hermes}/bin/hermes ${hermesConfigFile} "capture=${greeterCapture}" "output_name=$real" "$@"
    fi
    exec ${hermes}/bin/hermes ${hermesConfigFile} "capture=${greeterCapture}" "$@"
  '';

  # Watchdog for the startup hang: either service occasionally hangs
  # mid-init without exiting (port 47984 never binds), so Restart=on-
  # failure never fires and the host is unreachable from clients until
  # manual intervention. A timer-driven health check restarts whichever
  # service is active, portless past 120s (normal init finishes in under
  # a minute). Inactive services are left alone — auto-restarting cannot
  # fix a broken unit, and the user unit's startLimit (5 per 500s) bounds
  # the restart loop; after it trips the watchdog sees a failed unit and
  # stands down.
  hermesWatchdog = pkgs.writeShellScript "hermes-watchdog" ''
    set -u

    port_open() { (exec 3<>/dev/tcp/127.0.0.1/47984) 2>/dev/null; }

    # $1 = unit name; 0 when it is active, portless, and stale (>120s
    # since activation).
    service_hung() {
      systemctl is-active --quiet "$1" || return 1
      port_open && return 1
      local enter now age
      enter=$(systemctl show "$1" -p ActiveEnterTimestampMonotonicUSec --value)
      [ -n "$enter" ] && [ "$enter" -gt 0 ] || return 1
      now=$(awk '{print int($1 * 1000000)}' /proc/uptime)
      age=$((now - enter))
      [ "$age" -gt 120000000 ]
    }

    # The user service wins any ambiguity: restarting it also re-runs
    # its ExecStartPre, which stops a stray greeter.
    if systemctl --user is-active --quiet hermes.service; then
      if service_hung hermes.service; then
        echo "watchdog: hermes hung portless past 120s, restarting"
        systemctl --user restart hermes.service
      fi
      exit 0
    fi
    if service_hung hermes-greeter.service; then
      echo "watchdog: hermes-greeter hung portless past 120s, restarting"
      # Allowed without a password by the polkit rule above.
      systemctl restart hermes-greeter.service
    fi
  '';

in
{
  options.modules.capabilities.hermes = {
    enable = lib.mkEnableOption "Moonlight/Artemis game streaming via Hermes";

    greeterWaylandUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        User that owns the pre-login greeter's Wayland runtime directory.
        When set, the greeter service waits for that user's wayland-*
        socket and captures it with wlr-screencopy instead of root KMS
        capture (root KMS hits EGL_BAD_MATCH importing the root capture
        frame on this host).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          cfg.greeterWaylandUser == null
          || builtins.hasAttr cfg.greeterWaylandUser config.users.users;
        message = ''
          modules.capabilities.hermes.greeterWaylandUser must name an
          existing system user when set.
        '';
      }
    ];

    # Virtual input devices: libvirtualhid creates the streamed pointer,
    # keyboard and touch devices through /dev/uinput and /dev/uhid; the
    # package's udev rules (60-hermes.rules) grant the active-seat user
    # access and tag libvirtualhid-created HID parents.
    hardware.uinput.enable = true;
    services.udev.packages = [ hermes ];

    environment.systemPackages = [
      hermes
      # Text clipboard sync — hermes shells out to wl-copy / wl-paste and
      # looks them up on PATH; system-wide install keeps the systemd user
      # manager's default PATH authoritative (see the header).
      pkgs.wl-clipboard
    ];

    # Moonlight/Artemis streaming ports (Sunshine lineage): 47984 HTTPS
    # pairing/API, 47989 HTTP/RTSP, 47990 HTTPS web UI, 48010 RTSP;
    # 47998/47999/48000 UDP for video, control and audio. mDNS discovery
    # rides the lan class's avahi instance — not re-declared here.
    networking.firewall = {
      allowedTCPPorts = [
        47984
        47989
        47990
        48010
      ];
      allowedUDPPorts = [
        47998
        47999
        48000
      ];
    };

    # Greeter session compositor config. compositor.customConfig REPLACES
    # the upstream embedded template (dux-greeter v2.0.0
    # core/internal/config/embedded/niri-greeter.kdl — copied verbatim
    # below, re-sync if that template ever grows new session essentials);
    # dms-greeter appends its own spawn-at-startup for the greeter UI on
    # top. The greeter session has no idle daemon, so nothing ever
    # DPMS-blanks it — the pre-login stream stays live indefinitely.
    services.displayManager.dux-greeter.compositor.customConfig = ''
      hotkey-overlay {
          skip-at-startup
      }
      environment {
          DMS_RUN_GREETER "1"
      }
      input {
          keyboard {
              xkb {
              }
              numlock
          }
          touchpad {
              tap
              natural-scroll
          }
          mouse {
          }
          trackpoint {
          }
      }
      gestures {
          hot-corners {
              off
          }
      }
      layout {
          background-color "#000000"
      }
    '';

    # Root system service: streams the greeter before any user logs in.
    # greetd registers the display-manager.service alias (see the NixOS
    # greetd module), so the requires/after dependency holds unchanged.
    systemd.services.hermes-greeter = {
      description = "Hermes — pre-login greeter stream";
      requires = [ "display-manager.service" ];
      after = [ "display-manager.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "root";
        Group = "root";
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
        ExecStart = hermesGreeterWrapper;
        Restart = "on-failure";
        # The wrapper exits 1 when the greeter session has no Wayland
        # socket (for example during a user-session handoff or logout).
        # Restarting that state every five seconds creates a DRM/capture
        # restart storm; leave the unit failed until the handoff
        # explicitly starts it again.
        RestartPreventExitStatus = 1;
        RestartSec = "5s";
      };
    };

    # Polkit rule: allow the logged-in user to stop/start hermes-greeter
    # from the user service's ExecStartPre/ExecStopPost without a
    # password prompt. Without this, the handoff fails because a
    # non-privileged user cannot manage a system-level systemd unit.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "hermes-greeter.service" &&
            subject.isInGroup("users")) {
          return polkit.Result.YES;
        }
      });
    '';

    # User service: streams the logged-in niri session over the direct
    # wlr-screencopy socket (no XDG Portal approval prompt). Handoff with
    # the greeter: on start, stop the greeter so the two never fight over
    # the DRM output; on stop (logout), bring the greeter back for the
    # next remote login. The one-second pause lets the old process
    # release the ports before the new one binds.
    systemd.user.services.hermes = {
      description = "Hermes — desktop stream host";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];

      startLimitIntervalSec = 500;
      startLimitBurst = 5;

      serviceConfig = {
        ExecStart = "${hermes}/bin/hermes ${hermesConfigFile}";
        ExecStartPre = [
          "${pkgs.systemd}/bin/systemctl stop hermes-greeter.service"
          "${pkgs.coreutils}/bin/sleep 1"
        ];
        ExecStopPost = [
          "${pkgs.systemd}/bin/systemctl start hermes-greeter.service"
        ];
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    systemd.user.services.hermes-watchdog = {
      unitConfig.Description = "Health check for the Hermes user/greeter services";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = hermesWatchdog;
      };
    };
    systemd.user.timers.hermes-watchdog = {
      unitConfig.Description = "Periodic Hermes health check";
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = "2min";
        Unit = "hermes-watchdog.service";
      };
      wantedBy = [ "timers.target" ];
    };
  };
}
