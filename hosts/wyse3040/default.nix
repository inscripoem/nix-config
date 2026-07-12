{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ./hardware.nix
  ];

  networking.hostName = "wyse3040";
}
