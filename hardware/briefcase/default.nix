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

  # KWin 6.5 + NVIDIA 580 explicit sync (linux-drm-syncobj-v1) workaround.
  # Symptoms: login freezes on SDDM/KSplash until a VT switch, or session
  # silently dies back to SDDM mid-startup. See docs/nvidia.md §4 for the
  # full diagnosis and the conditions under which this can be removed.
  environment.sessionVariables.KWIN_DRM_DISABLE_EXPLICIT_SYNC = "1";

  networking.hostName = "briefcase";
}
