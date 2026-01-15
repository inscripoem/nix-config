{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
  ];

  # Bootloader configuration for Briefcase (UEFI)
  # Assumes UEFI system as disk-config.nix defines an ESP partition
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "briefcase";
}
