{ lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ./hardware.nix
  ];

  networking.hostName = "wyse3040";

  # dbus-broker's upstream unit ships PrivateTmp=true, which trips this
  # box's spawn-EPERM quirk (see hardware.nix): the broker cannot start and
  # every dbus-dependent service (avahi, logind, wpa_supplicant) falls over,
  # leaving the machine unreachable. Pin the classic reference daemon.
  services.dbus.implementation = lib.mkForce "dbus";

  # Builder SSH key deployed via sops-nix — no manual key generation
  # needed on the target. The public half is in vars.builderClientKeys.
  sops.secrets."wyse3040_builder_ed25519" = {
    sopsFile = ../../secrets/builder.yaml;
    path = "/persist/root/.ssh/builder_ed25519";
    owner = "root";
    mode = "0400";
  };
}
