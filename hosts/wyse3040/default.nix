{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ./hardware.nix
    ./impermanence.nix
    ./remote-build.nix
    ./wear-leveling.nix
  ];

  networking.hostName = "wyse3040";
}
