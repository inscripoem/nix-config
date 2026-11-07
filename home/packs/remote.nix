# Remote-access clients. Netcatty is the first member: upstream's own Nix
# packaging (AppImage extract + FHS wrap, x86_64/aarch64 linux only),
# exposed as pkgs.netcatty by the overlay in lib/nixosModules.nix because
# HM sharedModules can't consume flake inputs directly. Upstream CI bumps
# nix/release.nix on every release, so `nix flake update netcatty` tracks
# the latest version.
#
# The --password-store flag is load-bearing: Chromium's keyring backend
# auto-detection reads XDG_CURRENT_DESKTOP, and niri is unknown to it, so
# safeStorage would silently fall back to basic_text — which Netcatty
# refuses (decryption is skipped, so synced enc:v1: placeholders never
# resolve to usable credentials). Same mechanism as the passwordStore arg
# defined in ./default.nix, consumed here the same way
# packs/ai/workbuddy.nix consumes it.
#
# openssh goes on PATH for the same FHS reason: Netcatty's mosh flow
# (electron/bridges/moshHandshake.cjs) bootstraps by spawning the SYSTEM
# ssh to run `mosh-server new` remotely — "macOS / Linux have it
# everywhere" per upstream, but inside the appimageTools FHS env on NixOS
# there is no ssh on PATH (desktop launch never carries
# /run/current-system/sw/bin), so the handshake dies before the bundled
# static mosh-client (resources/mosh/mosh-client, runs fine on NixOS) is
# ever reached. The bundled client needs nothing else; mosh-server runs on
# the remote host.
{ config, lib, pkgs, passwordStore, ... }:
let
  cfg = config.packs.remote;
in
{
  options.packs.remote.netcatty.enable = lib.mkEnableOption
    "netcatty — SSH/SFTP workspace client (upstream flake packaging)";

  config = lib.mkIf cfg.netcatty.enable {
    home.packages = [
      (pkgs.symlinkJoin {
        name = "netcatty";
        paths = [ pkgs.netcatty ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/netcatty \
            --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.openssh ]} \
            --add-flags "--password-store=${passwordStore}"
        '';
      })
    ];
  };
}
