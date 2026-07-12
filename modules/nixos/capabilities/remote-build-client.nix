# Remote-build client: distribute Nix builds to vars.builders.
#
# 1.8 GB RAM makes local Nix builds impractical on resource-constrained
# hosts; every derivation gets farmed out to hosts listed in
# vars.builders. The client does no local building (max-jobs = 0).
#
# The SSH key at /persist/root/.ssh/builder_ed25519 is deployed
# declaratively via sops-nix (secrets/builder.yaml → sops.secrets on
# wyse3040). Each remote-build client gets its own keypair; the public
# half lives in keys/ and is referenced by vars.builderClientKeys.

{ config, lib, vars, ... }:
let cfg = config.modules.capabilities.remote-build-client;
in {
  options.modules.capabilities.remote-build-client.enable =
    lib.mkEnableOption "distribute Nix builds to vars.builders";
  config = lib.mkIf cfg.enable {
    nix.distributedBuilds = true;

    # Never build anything locally.
    nix.settings.max-jobs = 0;

    # Fall back to binary caches if a remote builder cannot produce.
    nix.settings.builders-use-substitutes = true;

    # Derive nix.buildMachines from the vars.builders pool.
    nix.buildMachines = lib.mapAttrsToList (_: b: {
      hostName = b.hostName;
      sshUser = b.sshUser;
      sshKey = "/persist/root/.ssh/builder_ed25519";
      system = builtins.head b.systems;
      systems = b.systems;
      protocol = "ssh-ng";
      maxJobs = b.maxJobs;
      speedFactor = b.speedFactor;
      supportedFeatures = b.supportedFeatures;
    }) vars.builders;
  };
}
