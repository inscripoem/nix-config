# Remote-access clients. Netcatty is the first member: upstream's own Nix
# packaging (AppImage extract + FHS wrap, x86_64/aarch64 linux only) is
# consumed through the netcatty flake input; upstream CI bumps
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
# The openssh PATH prefix is a fallback for hosts whose system profile
# has no ssh at all: netcatty's mosh flow (electron/bridges/
# moshHandshake.cjs) bootstraps by spawning the SYSTEM ssh to run
# `mosh-server new` remotely, resolved via PATH. A standard NixOS desktop
# already provides it inside the sandbox (systemd --user's PATH carries
# /run/current-system/sw/bin and buildFHSEnv bind-mounts /run wholesale);
# the bundled mosh-client (resources/mosh/mosh-client) is a static Rust
# binary and needs nothing.
#
# The fhs-bin/ssh shim is the actual fix. That spawned ssh reads the
# home-manager-managed ~/.ssh/config — a symlink to a root-owned nix
# store file — and unprivileged bwrap forces a user namespace mapping
# only the invoking uid (bubblewrap DWIMs unshare-user for non-root;
# setuid mode was removed upstream), so store files surface as the
# overflowuid 65534 inside. openssh's default user config always carries
# the ownership check — `st_uid != 0 && st_uid != getuid()` ||
# mode & 022 (openssh 10.6p1 readconf.c:2652, applied to ~/.ssh/config
# via ssh.c:584) — which 65534 fails: "Bad owner or permissions" kills
# the handshake before any connection. No flag or env skips that check
# for the default config; -F is the only bypass and is itself not
# re-checked (ssh.c:574), so the shim hands openssh a user-owned
# snapshot (-F) refreshed on mtime; everything else (known_hosts, agent)
# keeps default resolution. Boundary: Include directives are
# force-checked (readconf.c:2129) and would still hit store paths if the
# HM config ever gains one; today it has none.
{ config, lib, pkgs, passwordStore, ... }:
let
  cfg = config.packs.remote;

  # See the header comment: hands openssh a user-owned snapshot of
  # ~/.ssh/config so its ownership check passes inside the FHS userns.
  sshShim = pkgs.writeShellScript "ssh" ''
    cfg="$HOME/.ssh/config"
    snap="''${XDG_CACHE_HOME:-$HOME/.cache}/netcatty-ssh/config"
    if [ -e "$cfg" ]; then
      mkdir -p "$(dirname "$snap")"
      if [ ! -e "$snap" ] || [ "$cfg" -nt "$snap" ]; then
        cp "$cfg" "$snap" && chmod 600 "$snap"
      fi
      exec ${pkgs.openssh}/bin/ssh -F "$snap" "$@"
    fi
    exec ${pkgs.openssh}/bin/ssh "$@"
  '';
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
          # --prefix prepends each time: the LAST --prefix wins the front of
          # PATH. fhs-bin (the shim) must shadow the real openssh bin.
          wrapProgram $out/bin/netcatty \
            --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.openssh ]} \
            --prefix PATH : $out/fhs-bin \
            --add-flags "--password-store=${passwordStore}"
          mkdir -p $out/fhs-bin
          ln -s ${sshShim} $out/fhs-bin/ssh
        '';
      })
    ];
  };
}
