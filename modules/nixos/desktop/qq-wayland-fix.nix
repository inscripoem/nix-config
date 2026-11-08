# QQ pinned + patched for native Wayland. Two pieces travel together:
#
# 1. programs.linuxqq-wayland-fix (upstream flake module) — LD_PRELOAD
#    fixes for QQ running in Wayland mode: in-app screenshot (captured
#    via wlr-screencopy, which niri implements), screen share (PipeWire +
#    portal ScreenCast, served by our gnome portal backend) and clipboard
#    (Wayland data-control). Requires xdg.portal, enabled in xdg-portal.nix.
# 2. The nixpkgs-qq pin (see flake.nix) — qq follows the nixpkgs rev the
#    fix tests against, so the fixes never run against an unadapted QQ
#    build. Bump via scripts/update-versions.sh --only=qq.
#
# The overlay reaches home.packages too (home-manager.useGlobalPkgs), so
# social.nix's qq resolves to the same pinned derivation the fix launcher
# uses. Scope matches QQ's own: desktop-class hosts only.
# NOTE: module args must be declared explicitly to be passed at all —
# `{ inputs, ... }` alone would leave `pkgs` undefined.
{ inputs, pkgs, vars, ... }:

{
  nixpkgs.overlays = [
    (_final: prev: {
      # nixpkgs-qq is a separate nixpkgs evaluation and does not inherit the
      # system's allowUnfree, so it is set explicitly here.
      qq = (import inputs.nixpkgs-qq {
        localSystem = prev.stdenv.hostPlatform.system;
        config.allowUnfree = true;
      }).qq;
    })
    # brings pkgs.linuxqq-wayland-fix, callPackage'd from our nixpkgs
    inputs.linuxqq-wayland-fix.overlays.default
  ];

  imports = [ inputs.linuxqq-wayland-fix.nixosModules.default ];
  programs.linuxqq-wayland-fix.enable = true;

  # Bake QQ_WAYLAND_FIX_ANGLE=off into the launcher itself. Without it the
  # launcher auto-selects ANGLE=vulkan, which crash-loops the GPU process
  # on dual-Intel-GPU hosts ("Unable to initialize SkSurface") and no
  # window ever appears — verified 2026-10-10. Session env is NOT a viable
  # alternative here: menu launches fork the launcher with the login-time
  # session environment, so environment.sessionVariables and the systemd
  # user manager env never reach it. Wrapping the binary is launch-path
  # independent. "off" keeps QQ's own default GL path (identical to stock
  # qq); the screenshot/share/clipboard fixes are unaffected.
  programs.linuxqq-wayland-fix.package =
    let
      base = pkgs.linuxqq-wayland-fix;
    in
    pkgs.symlinkJoin {
      pname = "linuxqq-wayland-fix-wrapped";
      version = base.version;
      paths = [ base ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram "$out/bin/linuxqq-wayland-fix" \
          --set QQ_WAYLAND_FIX_ANGLE off
        # Upstream bakes the base store path into the desktop entry's Exec,
        # which would bypass the wrapper entirely — repoint it at ours.
        # The joined share/applications entry is a read-only symlink into
        # the base package, so drop the link and write a fresh file.
        rm -f "$out/share/applications/linuxqq-wayland-fix.desktop"
        substitute \
          "${base}/share/applications/linuxqq-wayland-fix.desktop" \
          "$out/share/applications/linuxqq-wayland-fix.desktop" \
          --replace-fail "${base}/bin/linuxqq-wayland-fix" "$out/bin/linuxqq-wayland-fix"
      '';
    };

  # QQ's in-call "sharing" toolbar (floating toplevel, title "屏幕共享";
  # identity verified 2026-10-28 via `niri msg windows`). Wayland clients
  # cannot self-position windows, so niri centers floating windows on
  # screen — pin it to top-center instead, matching QQ on Windows/KDE.
  # relative-to="top" (side-only anchor) centers the window on that edge
  # in working-area coordinates, so it lands below the DMS bar at any
  # resolution/scale — no hardcoded x/y. The rule lives here, next to the
  # fix that makes the window exist at all, not in home/desktop/niri.
  # Reaching into home-manager from this NixOS module is safe: every
  # desktop-class host imports the niri HM module (home/desktop/default.nix
  # → ./niri). The same-titled fullscreen border window (whose buffer
  # borderfix detaches) also matches; repositioning a buffer-less window
  # is a no-op.
  home-manager.users.${vars.username}.programs.niri.settings.window-rules = [
    {
      matches = [ { app-id = "^QQ$"; title = "^屏幕共享$"; } ];
      # relative-to="top" (side-only anchor) centers the window on that
      # edge in working-area coordinates, so it lands below the DMS bar
      # at any resolution/scale. x compensates for QQ committing a
      # transposed 86px-wide initial size: niri computes the position
      # once at float-entry with that size (left = W/2 - 86/2) and never
      # recenters on resize, so the 607px-wide toolbar ends up
      # (607-86)/2 = 260.5px right of center. Measured 2026-11-09:
      # left=917 on a 1920 output; with x=-260.5 it lands at 656.5 =
      # exact center. Re-verify after bumping the qq pin.
      default-floating-position = {
        x = -260.5;
        y = 0;
        relative-to = "top";
      };
    }
  ];
}
