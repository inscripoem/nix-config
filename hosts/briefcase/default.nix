{ ... }:

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

  # The budget H410 board + Comet Lake combo silently drops the PCIe
  # link when the CPU enters deep C-states (C2/C3). The GPU falls off
  # the bus → hard freeze with zero logs from kernel panic detectors,
  # NMI watchdog, or pstore. Restrict the CPU to C1 at deepest to
  # keep the PCIe link alive.
  boot.kernelParams = [ "intel_idle.max_cstate=1" ];

  # The OC watchdog is useless on this board and would otherwise win the
  # /dev/watchdog registration race; iTCO_wdt is the one systemd should feed.
  boot.blacklistedKernelModules = [ "intel_oc_wdt" ];

  # Feed the PCH iTCO watchdog (heartbeat=30s) so a whole-machine hang
  # auto-resets instead of waiting for a manual power cycle. RuntimeWatchdogSec
  # makes systemd ping it every 15s; keep this below the 30s hardware timeout.
  # Last line of defense for the silent hard-hangs documented in
  # docs/hard-hang-cstate.md, which fall below kernel panic visibility.
  systemd.settings.Manager.RuntimeWatchdogSec = "30s";

  networking.hostName = "briefcase";

  # Palworld dedicated server — game port (UDP only; RCON/REST API would
  # need extra TCP ports but are disabled by default).
  networking.firewall.allowedUDPPorts = [ 8211 ];

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
