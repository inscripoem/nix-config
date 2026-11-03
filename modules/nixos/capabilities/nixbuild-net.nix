# Remote Nix builds on nixbuild.net (eu.nixbuild.net).
#
# Opt-in per host through `modules.capabilities.nixbuild-net.enable`, so
# only hosts that should spend the account's CPU budget configure the
# builder and pull in the SSH key. Unlike remote-build-client this keeps
# local capacity: nix-daemon prefers the remote builder and falls back to
# local jobs when it is unreachable or saturated. `nhsl` (force local) and
# `nhsr` (force remote) override the choice for one switch; see
# home/core/shell.nix.
#
# The private key lives in secrets/nixbuild.yaml and decrypts to
# /run/secrets at activation, readable only by root (owner of nix-daemon).
# It is deliberately not in the SSH agent: root cannot reach a user agent
# and an agent dies with the login session, while the file survives
# reboots. A passwordless key is required because nix-daemon cannot prompt.
#
# nixbuild.net builds i686-linux, x86_64-linux, aarch64-linux and
# armv7l-linux only — Darwin hosts cannot use it. See docs/nixbuild-net.md.

{ config, lib, ... }:
let cfg = config.modules.capabilities.nixbuild-net;
in
{
  options.modules.capabilities.nixbuild-net = {
    enable =
      lib.mkEnableOption "remote Nix builds on nixbuild.net (eu.nixbuild.net)";
    keyName = lib.mkOption {
      type = lib.types.str;
      default = "nixbuildnet_builder_ed25519";
      description = ''
        SOPS key in secrets/nixbuild.yaml holding the private half of the
        SSH key registered with the nixbuild.net account.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."${cfg.keyName}" = {
      sopsFile = ../../../secrets/nixbuild.yaml;
      owner = "root";
      mode = "0400";
      # A rotated key must not leave nix-daemon holding a dead connection.
      restartUnits = [ "nix-daemon.service" ];
    };

    # Root's SSH client config: nix-daemon is the process that connects.
    programs.ssh.extraConfig = ''
      Host eu.nixbuild.net
        ServerAliveInterval 60
        IdentityFile ${config.sops.secrets."${cfg.keyName}".path}
    '';

    # Nix cannot answer a host-key prompt.
    programs.ssh.knownHosts.nixbuild = {
      hostNames = [ "eu.nixbuild.net" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
    };

    nix.distributedBuilds = true;

    # Let the builder substitute instead of rebuilding what a cache already
    # holds: CPU time is what this account pays for.
    nix.settings.builders-use-substitutes = true;

    nix.buildMachines = [
      {
        hostName = "eu.nixbuild.net";
        system = "x86_64-linux";
        maxJobs = 100;
        supportedFeatures = [
          "benchmark"
          "big-parallel"
          "ca-derivations"
          "kvm"
          "nixos-test"
        ];
      }
    ];
  };
}
