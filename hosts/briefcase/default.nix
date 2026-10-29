{ pkgs, ... }:

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

  # Feed the PCH iTCO watchdog (heartbeat=30s) so a whole-machine hang
  # auto-resets instead of waiting for a manual power cycle. RuntimeWatchdogSec
  # makes systemd ping it every 15s; keep this below the 30s hardware timeout.
  # Kept from the H410 era (docs/hard-hang-cstate.md) as a recovery-only net
  # while the B760M platform is on observation; verified on this board that
  # iTCO_wdt owns /sys/class/watchdog/watchdog0.
  systemd.settings.Manager.RuntimeWatchdogSec = "30s";

  networking.hostName = "briefcase";

  # Palworld dedicated server — game port (UDP only; RCON/REST API would
  # need extra TCP ports but are disabled by default).
  networking.firewall.allowedUDPPorts = [ 8211 ];

  # Pull in linux-firmware so Intel AX210 (and friends) get iwlwifi-*.ucode.
  # Without this the PCIe Wi-Fi half of the card fails to probe even though
  # USB-side Bluetooth keeps working with in-tree btusb.
  hardware.enableRedistributableFirmware = true;

  # SayoDevice CM6K foot pedal (8089:000c): user-space consumers open
  # its nodes directly — Python evdev workers read the event nodes
  # (no logind TakeDevice path like the compositor), and the vendor web
  # configurator (WebUSB/WebHID) opens the usb/hidraw nodes. uaccess
  # grants the active seat user only; the serial pins the grant to this
  # one unit. Numbered <70 so the tag is set before 73-seat-late.rules,
  # which invokes the uaccess builtin.
  services.udev.packages = [
    (pkgs.writeTextDir "lib/udev/rules.d/70-cm6k-pedal.rules" ''
      SUBSYSTEM=="input", KERNEL=="event*", ATTRS{idVendor}=="8089", ATTRS{idProduct}=="000c", ATTRS{serial}=="03CDABF106D3BD9170FFFFFFFF0300", TAG+="uaccess"
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="8089", ATTRS{idProduct}=="000c", ATTRS{serial}=="03CDABF106D3BD9170FFFFFFFF0300", TAG+="uaccess"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="8089", ATTRS{idProduct}=="000c", ATTRS{serial}=="03CDABF106D3BD9170FFFFFFFF0300", TAG+="uaccess"
    '')
  ];

  # Enable Tailscale client-side routing tweaks (rp_filter = loose).
  # Required for using a peer as exit node or accepting subnet routes
  # advertised by other tailnet nodes. The tailscale capability enables
  # the base daemon; this host opts into routing features.
  services.tailscale.useRoutingFeatures = "client";
}
