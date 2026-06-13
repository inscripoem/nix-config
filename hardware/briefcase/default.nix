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

  # NVIDIA driver configuration — see docs/nvidia.md for the rationale
  # behind every flag (open=false on TU106, modesetting for Wayland,
  # powerManagement to avoid resume-time flicker).
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = false;
  hardware.nvidia.modesetting.enable = true;
  hardware.nvidia.powerManagement.enable = true;

  networking.hostName = "briefcase";
}
