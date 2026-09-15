{ pkgs, ... }:

{
  # Phase 4 transfers the package, daemon, build users, and nix.conf to
  # nix-darwin. Keep the installer-owned APFS mount and global profile.
  # Preparation and rollback: docs/darwin-lix.md.
  nix = {
    enable = true;
    package = pkgs.lix;

    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      always-allow-substitutes = true;
      trusted-substituters = [ "https://cache.lix.systems" ];
      trusted-public-keys = [
        "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
      ];
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
