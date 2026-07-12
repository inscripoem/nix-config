# Wyse3040 as a remote-build client.
#
# 1.8 GB RAM makes local Nix builds impractical; every derivation gets
# farmed out to hosts listed in vars.builders (currently briefcase).
# The wyse itself does no local building (max-jobs = 0).
#
# The SSH key at /persist/root/.ssh/builder_ed25519 must be generated
# post-install and its public half added to vars.builderClientKeys;
# see docs/wyse3040-install.md §7 for that step.

{ vars, lib, ... }:

{
  nix.distributedBuilds = true;

  # Never build anything locally: RAM would OOM long before completion.
  nix.settings.max-jobs = 0;

  # If a remote builder cannot produce a derivation, fall back to
  # substituting from the configured binary caches rather than crashing.
  nix.settings.builders-use-substitutes = true;

  # Derive nix.buildMachines from the vars.builders pool. Adding a new
  # builder in vars/ automatically becomes a new upstream here on the
  # next rebuild.
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
}
