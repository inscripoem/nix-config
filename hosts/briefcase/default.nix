{ config, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    # Active GPU profile. Swap this line — and only this line — when the
    # card changes. Old profiles in ./gpu/ stay around for swap-back.
    ./gpu/nvidia-pascal.nix
    # Opt in to the remote-builder role: briefcase accepts nix build
    # jobs from any client whose key is in vars.builderClientKeys.
    ../../modules/nixos/nix-builder.nix
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
  # advertised by other tailnet nodes. See system/tailscale.nix for the
  # shared portion of the configuration.
  services.tailscale.useRoutingFeatures = "client";

  # Deployment CLIs. briefcase is the sole deployer for the fleet;
  # colmena/deploy-rs binaries live here so `just apply` / `just
  # safe-apply` can invoke them directly.
  environment.systemPackages = [
    inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena
    inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.deploy-rs
  ];
}
