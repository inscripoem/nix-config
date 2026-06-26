{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    # Active GPU profile. Swap this line — and only this line — when the
    # card changes. Old profiles in ./gpu/ stay around for swap-back.
    ./gpu/nvidia-pascal.nix
  ];

  # Bootloader configuration for Briefcase (UEFI)
  # Assumes UEFI system as disk-config.nix defines an ESP partition
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "briefcase";
}
