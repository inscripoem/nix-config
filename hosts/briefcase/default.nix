{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    # Active GPU profile. Swap this line — and only this line — when the
    # card changes. Old profiles in ./gpu/ stay around for swap-back.
    ./gpu/intel-arc-a380.nix
  ];

  # Bootloader configuration for Briefcase (UEFI)
  # Assumes UEFI system as disk-config.nix defines an ESP partition
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "briefcase";

  # Pull in linux-firmware so Intel AX210 (and friends) get iwlwifi-*.ucode.
  # Without this the PCIe Wi-Fi half of the card fails to probe even though
  # USB-side Bluetooth keeps working with in-tree btusb.
  hardware.enableRedistributableFirmware = true;

  # Enable Tailscale client-side routing tweaks (rp_filter = loose).
  # Required for using a peer as exit node or accepting subnet routes
  # advertised by other tailnet nodes. The tailscale capability enables
  # the base daemon; this host opts into routing features.
  services.tailscale.useRoutingFeatures = "client";
}
