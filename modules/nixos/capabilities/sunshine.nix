# Sunshine — self-hosted game stream host for Moonlight.
#
# Why Sunshine (and not KRDP / RustDesk / Parsec / krfb):
#
#   Sunshine captures through KMS on this machine, so it serves the
#   greetd/DMS greeter before login and any session compositor after
#   login (niri and Plasma Wayland alike). KMS requires cap_sys_admin,
#   which the upstream module grants via a security wrapper when
#   services.sunshine.capSysAdmin is enabled. The X11 architecture
#   was originally chosen to work around NVIDIA proprietary driver
#   issues (Turing RTX 2060S, see docs/nvidia.md), when capture
#   ran over XShm and the greeter's X server was the only pre-login
#   capture target; with the Arc A380 and KMS capture the greeter
#   backend no longer constrains capture, and the greeter is now
#   greetd + Dux Greeter (see modules/nixos/desktop/display-managers.nix).
#
#   Sunshine is chosen over the alternatives:
#     - KRDP: Wayland-only (kcm hides on X11), no Linux host path.
#     - RustDesk: works on X11 but has no NixOS *host* module
#       (only `services.rustdesk-server` for self-hosting the relay),
#       and `rustdesk --service` (unattended) needs a sudo+setuid
#       wrapper hack under NixOS.
#     - Parsec: no Linux host at all (Windows/macOS only) — dead on
#       arrival for this NixOS box.
#     - krfb (VNC): pure CPU compression, too laggy for cross-region
#       use (HK <-> SZ).
#
#   Both the pre-login and post-login services capture via KMS and
#   encode with the Intel Arc A380's media engines, need no third-party
#   account/signaling server — connectivity rides on the existing
#   Tailscale tailnet. See docs/remote-desktop.md for the full
#   rationale, alternatives comparison, port map, and usage.
#
# How Sunshine runs before login (Windows-RDP-like experience):
#   Two systemd services cooperate:
#     1. sunshine-greeter (system, root) — starts after display-manager,
#        grabs the greetd/DMS greeter session. Moonlight connects and
#        sees the login screen.
#     2. sunshine (user, via NixOS module) — starts with graphical-
#        session.target when a user logs in. ExecStartPre stops
#        sunshine-greeter; ExecStopPost restarts it on logout.
#   This avoids auto-login (which breaks KWallet/gnome-keyring because
#   PAM never sees a password -> WiFi doesn't auto-connect, Vivaldi's
#   cookie store is lost, etc.). See docs/remote-desktop.md.
#
# What the NixOS module already does for us (do NOT re-declare here):
#   - hardware.uinput.enable = true       (kernel uinput module + perms)
#   - services.udev.packages += sunshine  (controller / udev rules)
#   - systemd.user.services.sunshine      (auto-starts with graphical-session)
#   - services.avahi publish.userServices (mDNS discovery for Moonlight;
#     uses mkDefault so it merges cleanly with the explicit avahi config
#     in the lan class)

{ config, lib, pkgs, vars, ... }:
let
  cfg = config.modules.capabilities.sunshine;

  # Reserved fake-output port (see the kernelParams block below).
  # Connector names are driver-enumerated: re-verify after any GPU swap
  # (hosts/briefcase/gpu sibling-profile workflow). The name also appears
  # in the greeter customConfig, the wrapper probe, home/desktop/niri/default.nix
  # (which reads it from the option below), docs/remote-desktop.md, and
  # the EDID generator header.
  fakeOutput = cfg.fakeOutputName;

  # The greeter is a Wayland (niri) session under greetd and capture is
  # pure KMS, so no X11 display/auth plumbing is needed here. HOME is
  # pointed at the user's home (not root's) so the Sunshine pairing
  # certificate is shared between the root service and the user service —
  # same UUID + certificate means Moonlight sees a single host regardless
  # of which service is currently streaming.
  #
  # output_name pins the capture to the output that carries the greeter:
  # niri's automatic placement puts the alphabetically-first connected
  # output first and opens the greeter UI there, so probe the same rule —
  # first connected DRM connector, fake output included (headless, it is
  # the only one). An unmatched name degrades to Sunshine's first-monitor
  # default with a journal warning (kmsgrab.cpp
  # map_display_name_to_monitor_index), never a hard failure.
  sunshineGreeterWrapper = pkgs.writeShellScript "sunshine-greeter" ''
    set -eu
    export HOME="/home/${vars.username}"
    export XDG_CONFIG_HOME="$HOME/.config"

    real="$(for c in /sys/class/drm/card*-*; do
      [ "$(cat "$c/status" 2>/dev/null)" = connected ] || continue
      name="''${c##*/}"
      echo "''${name#*-}"
      break
    done)"
    output="''${real:-${fakeOutput}}"

    exec ${pkgs.sunshine}/bin/sunshine "output_name=$output" "$@"
  '';
in {
  options.modules.capabilities.sunshine = {
    enable = lib.mkEnableOption "Moonlight/Sunshine game streaming";

    # Single source of truth for the fake-output connector name. Required
    # (no default) and set by each enabling host: which port is free is
    # host-specific physical knowledge — the GPU's connector enumeration
    # and which ports real monitors occupy. Omitting it fails evaluation
    # loudly at the point of use instead of silently forcing a port that
    # may have a real monitor on it. The session layer
    # (home/desktop/niri/default.nix) reads it through osConfig and gates on
    # `enable`, so hosts without the capability carry nothing.
    fakeOutputName = lib.mkOption {
      type = lib.types.str;
      description = ''
        DRM connector name reserved as the fake streaming output. Must
        match the connector the drm.edid_firmware kernel param forces;
        re-verify against the actual enumeration after a GPU swap.
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    services.sunshine = {
      enable = true;
      openFirewall = true;
      # KMS capture for both services (see header): the wrapper grants
      # cap_sys_admin to the user service binary, mirroring what the
      # root pre-login service already has.
      capSysAdmin = true;
    };

    # KWin 6.7+ enables DRM overlay planes by default on Intel GPUs,
    # which breaks Sunshine's KMS capture under Plasma Wayland: kmsgrab
    # pins a single plane, so content on other planes is missing from
    # the stream and the pinned plane being released (fb_id 0) freezes
    # capture with per-frame "Couldn't get drm fb" timeouts (upstream
    # LizardByte/Sunshine#5373). Keeping KWin composing on the primary
    # plane only fixes Plasma streaming; niri and the greeter session
    # never used overlays, so they are unaffected. The env var is read
    # at kwin startup, so a session restart (not just service restart)
    # is required after toggling.
    environment.sessionVariables.KWIN_USE_OVERLAYS = "0";

    # ── Fake streaming output (software dummy plug) ─────────────────────
    #
    # A GPU keeps no CRTC lit when nothing is connected, so a headless
    # machine has no framebuffer to stream at all — every capture backend
    # needs an active display. Instead of a hardware dummy plug, the
    # reserved port is force-enabled at the DRM level and fed a generated
    # EDID (sunshine-fake-edid.bin: preferred 3840x2160@60, the CEA-861
    # VIC 97 timing, plus a 1920x1080@60 standard timing). Every
    # compositor and Sunshine see one constant "monitor" no matter what
    # is plugged in on other ports; the streamed picture never drifts
    # with the hardware.
    #
    # The port must be HDMI, not DisplayPort: a forced DP connector has
    # no DPCD (there is no physical sink to report link capabilities),
    # so i915 validates modes against the fallback link and only
    # 640x480 survives — observed live on the A380, 2026-10-28. HDMI
    # has no DPCD dependency; its mode validation reads the limits
    # straight from the injected EDID (max dotclock 600 MHz here).
    #
    # Port roles on briefcase:
    #   DP-1, HDMI-A-2  : real monitors (true EDID, native modes)
    #   HDMI-A-1        : reserved fake output — do NOT plug a real
    #                     monitor in here; the forced EDID shadows it
    #
    # Params take effect at boot; the EDID is delivered through
    # /lib/firmware/edid/ (request_firmware path the kernel param names).
    boot.kernelParams = [
      "video=${fakeOutput}:e"
      "drm.edid_firmware=${fakeOutput}:edid/sunshine-fake.bin"
    ];
    hardware.firmware = [
      (pkgs.runCommand "sunshine-fake-edid" { } ''
        mkdir -p $out/lib/firmware/edid
        install -Dm644 ${./sunshine-fake-edid.bin} \
          $out/lib/firmware/edid/sunshine-fake.bin
      '')
    ];

    # Greeter session output config. compositor.customConfig REPLACES the
    # upstream embedded template (dux-greeter v2.0.0
    # core/internal/config/embedded/niri-greeter.kdl — copied verbatim
    # below, re-sync if that template ever grows new session essentials);
    # dms-greeter appends its own spawn-at-startup for the greeter UI on
    # top. The fake output is pinned to its 1080p standard timing — the
    # same mode the daily session and the real monitor run, so login and
    # post-login screens are logically identical. The greeter session
    # has no idle daemon, so nothing ever DPMS-blanks it — the pre-login
    # stream stays live indefinitely.
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
      output "${fakeOutput}" {
          mode "1920x1080@60.000"
      }
    '';

    # Root system service: captures the greeter before any user logs in.
    # greetd registers the display-manager.service alias (see the NixOS
    # greetd module), so the requires/after dependency holds unchanged.
    # Moonlight connects and sees the DMS greeter — type the password and
    # the handoff to the user service happens.
    systemd.services.sunshine-greeter = {
      description = "Sunshine — pre-login greeter stream";
      requires = [ "display-manager.service" ];
      after = [ "display-manager.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "root";
        Group = "root";
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
        ExecStart = sunshineGreeterWrapper;
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    # Polkit rule: allow the logged-in user to stop/start sunshine-greeter
    # from the user service's ExecStartPre/ExecStopPost without a
    # password prompt. Without this, the handoff fails because a
    # non-privileged user cannot manage a system-level systemd unit.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "sunshine-greeter.service" &&
            subject.isInGroup("users")) {
          return polkit.Result.YES;
        }
      });
    '';

    # User service handoff: when the user-level Sunshine starts (user
    # logged in), stop the root sunshine-greeter so they don't both grab
    # the DRM output. When the user service stops (logout), restart
    # sunshine-greeter so the greeter is streamable again for the next
    # remote login.
    systemd.user.services.sunshine = {
      serviceConfig = {
        ExecStartPre = [
          "${pkgs.systemd}/bin/systemctl stop sunshine-greeter.service"
          "${pkgs.coreutils}/bin/sleep 1"  # let old process release ports before binding
        ];
        ExecStopPost = [
          "${pkgs.systemd}/bin/systemctl start sunshine-greeter.service"
        ];
      };
    };
  };
}
