# BlueZ Bluetooth stack.
#
# bluetoothd is resident by nature: it has no on-demand activation and
# BLE client libraries (Bleak and friends) go through its D-Bus API
# for every scan and connect. Footprint is a few MB.
{ config, lib, ... }:

let cfg = config.modules.capabilities.bluetooth;
in {
  options.modules.capabilities.bluetooth.enable =
    lib.mkEnableOption "Bluetooth via BlueZ (resident bluetoothd, adapter powered on at boot)";

  config = lib.mkIf cfg.enable {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      # Exposes experimental D-Bus APIs. Needed for BLE bearer selection
      # (BLE-only peripherals via Bleak) without touching other devices'
      # transport. Stable profiles (A2DP, GATT) behave identically.
      settings.General.Experimental = true;
    };
  };
}
