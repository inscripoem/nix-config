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
{ inputs, ... }:

{
  nixpkgs.overlays = [ (_final: prev: {
    # nixpkgs-qq is a separate nixpkgs evaluation and does not inherit the
    # system's allowUnfree, so it is set explicitly here.
    qq = (import inputs.nixpkgs-qq {
      localSystem = prev.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    }).qq;
  }) ];

  imports = [ inputs.linuxqq-wayland-fix.nixosModules.default ];
  programs.linuxqq-wayland-fix.enable = true;
}
