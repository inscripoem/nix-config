{ config, pkgs, ... }:

{
  # Disk health surveillance: pairs with kernel.nix (which panics + reboots
  # when the machine falls over) by warning us *before* the SSD dies. Added
  # after the July 2026 briefcase incident where nvme0 SMART showed
  # percentage_used=92%, num_err_log_entries=9588, and the symptom "cold
  # boot recovers, warm boot has no boot entry" pointed at NVMe controller
  # flakiness, not filesystem corruption.
  environment.systemPackages = with pkgs; [
    smartmontools
    nvme-cli
  ];

  services.smartd = {
    enable = true;
    # Scan every attached ATA/NVMe device with a sensible default policy
    # instead of hand-listing paths (regenerable across hosts).
    autodetect = true;
    # Match KIOXIA EXCERIA's own Warning=72C / Critical=90C envelope
    # instead of smartd's very-conservative 45/55 defaults, otherwise
    # every `nhs` write burst fires a false alarm.
    defaults.autodetected = "-a -o on -S on -n standby,q -s (S/../.././02|L/../../6/03) -W 4,60,75";
    # Broadcast to every tty so we notice even outside journalctl.
    notifications.wall.enable = true;
  };
}
