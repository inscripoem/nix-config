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

  # NVIDIA driver configuration
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = true;

  networking.hostName = "briefcase";
}
