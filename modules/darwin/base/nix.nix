{ pkgs, ... }:

{
  # The installer phase originally deployed Lix (lix-installer, release
  # tarballs); nix-darwin took over its package, daemon, build users, and
  # nix.conf, keeping the installer-owned APFS mount and global profile.
  # 2026-10-17: switched the package to upstream Nix — nixpkgs' lix
  # expression was broken for 2.95.x (stale -Dmimalloc flag) with no darwin
  # binaries on any cache, and the installer-experience rationale for lix
  # had expired once nix-darwin owned the daemon. History and recovery:
  # docs/darwin-lix.md.
  nix = {
    enable = true;
    package = pkgs.nix;

    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      always-allow-substitutes = true;
      bash-prompt-prefix = ''(nix:$name)\040'';
      max-jobs = "auto";
    };

    # Keep the flake lookup without introducing a missing root channel.
    nixPath = [ "nixpkgs=flake:nixpkgs" ];
    gc.automatic = false;
    optimise.automatic = false;
  };

  # Pin unqualified nixpkgs lookups to the system's locked input.
  nixpkgs.flake = {
    setNixPath = true;
    setFlakeRegistry = true;
  };

  services.nix-daemon.logFile = "/var/log/nix-daemon.log";
}
