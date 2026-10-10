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
{ inputs, pkgs, ... }:

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
      name = "linuxqq-wayland-fix-wrapped";
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
}
