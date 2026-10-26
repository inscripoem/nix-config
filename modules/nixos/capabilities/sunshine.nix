# Sunshine — self-hosted game stream host for Moonlight.
#
# Why Sunshine (and not KRDP / RustDesk / Parsec / krfb):
#
#   Sunshine captures through KMS on this machine, so it serves the
#   SDDM greeter before login and any session compositor after login
#   (niri and Plasma Wayland alike). KMS requires cap_sys_admin, which
#   the upstream module grants via a security wrapper when
#   services.sunshine.capSysAdmin is enabled. The X11 architecture
#   below was originally chosen to work around NVIDIA proprietary
#   driver issues (Turing RTX 2060S, see docs/nvidia.md), when capture
#   ran over XShm and the greeter's X server was the only pre-login
#   capture target; with the Arc A380 and KMS capture the greeter
#   backend no longer constrains capture, but the known-good X11 SDDM
#   setup is retained.
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
#     1. sunshine-sddm (system, root) — starts after display-manager,
#        grabs the SDDM X11 greeter on :0. Moonlight connects and sees
#        the login screen.
#     2. sunshine (user, via NixOS module) — starts with graphical-
#        session.target when a user logs in. ExecStartPre stops
#        sunshine-sddm; ExecStopPost restarts it on logout.
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

  # SDDM 0.20+ on NixOS writes the X auth cookie to /run/sddm/xauth_*
  # (root-readable). The root sunshine-sddm service must set
  # XAUTHORITY to this file so Sunshine can authenticate to the X
  # server that SDDM started on :0. With KMS capture these X11
  # variables are not needed, but they keep the X11 capture fallback
  # working when no DRM output can be enumerated. The filename is
  # random, so we find it at service start time. HOME is pointed at
  # the user's home (not root's) so the Sunshine pairing certificate is
  # shared between the root service and the user service — same UUID +
  # certificate means Moonlight sees a single host regardless of which
  # service is currently streaming.
  sunshineSddmWrapper = pkgs.writeShellScript "sunshine-sddm" ''
    set -eu
    # Find SDDM's X auth cookie (root-readable, random suffix).
    XAUTH_FILE="$(find /run/sddm/ -name 'xauth_*' -type f 2>/dev/null | head -1)"
    if [ -n "$XAUTH_FILE" ]; then
      export XAUTHORITY="$XAUTH_FILE"
    fi
    export DISPLAY=":0"
    export HOME="/home/${vars.username}"
    export XDG_CONFIG_HOME="$HOME/.config"
    exec ${pkgs.sunshine}/bin/sunshine "$@"
  '';
in {
  options.modules.capabilities.sunshine.enable =
    lib.mkEnableOption "Moonlight/Sunshine game streaming";
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
    # plane only fixes Plasma streaming; niri and the SDDM greeter
    # never used overlays, so they are unaffected. The env var is read
    # at kwin startup, so a session restart (not just service restart)
    # is required after toggling.
    environment.sessionVariables.KWIN_USE_OVERLAYS = "0";

    # Root system service: captures the SDDM X11 greeter before any user
    # logs in. Moonlight connects and sees the SDDM login screen — type
    # the password and the handoff to the user service happens.
    systemd.services.sunshine-sddm = {
      description = "Sunshine — pre-login SDDM greeter stream";
      requires = [ "display-manager.service" ];
      after = [ "display-manager.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "root";
        Group = "root";
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
        ExecStart = sunshineSddmWrapper;
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    # Polkit rule: allow the logged-in user to stop/start sunshine-sddm
    # from the user service's ExecStartPre/ExecStopPost without a
    # password prompt. Without this, the handoff fails because a
    # non-privileged user cannot manage a system-level systemd unit.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "sunshine-sddm.service" &&
            subject.isInGroup("users")) {
          return polkit.Result.YES;
        }
      });
    '';

    # User service handoff: when the user-level Sunshine starts (user
    # logged in), stop the root sunshine-sddm so they don't both grab :0.
    # When the user service stops (logout), restart sunshine-sddm so the
    # SDDM greeter is streamable again for the next remote login.
    systemd.user.services.sunshine = {
      serviceConfig = {
        ExecStartPre = [
          "${pkgs.systemd}/bin/systemctl stop sunshine-sddm.service"
          "${pkgs.coreutils}/bin/sleep 1"  # let old process release ports before binding
        ];
        ExecStopPost = [
          "${pkgs.systemd}/bin/systemctl start sunshine-sddm.service"
        ];
      };
    };
  };
}
