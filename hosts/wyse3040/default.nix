{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ./hardware.nix
  ];

  networking.hostName = "wyse3040";

  # Builder SSH key deployed via sops-nix — no manual key generation
  # needed on the target. The public half is in vars.builderClientKeys.
  sops.secrets."wyse3040_builder_ed25519" = {
    sopsFile = ../../secrets/builder.yaml;
    path = "/persist/root/.ssh/builder_ed25519";
    owner = "root";
    mode = "0400";
  };
}
