# fan-argb — CPU fan duty and motherboard ARGB control for hosts with
# the Maxsun MS-Terminator B760M D4 board (briefcase since the
# 2026-10-26 platform swap). Two independent hardware chains:
#
#   * Fan duty: Nuvoton NCT6798 SuperIO (isa-0290), nct6775 driver.
#     All case fans are daisy-chained on CPU_FAN = fan2/pwm2. Reads
#     (RPM / pwm / temps) are world-readable sysfs; writes are
#     root-only and exposed to the desktop session through the
#     fan-set@<duty>.service template plus the polkit rule below.
#   * ARGB: ENE 6K7750 USB controller (0cf2:7750). The hidraw
#     interface is a decoy (all transfers STALL); real control is raw
#     USB vendor control transfers, handled by the ene-fanctl CLI in
#     pkgs/. The udev rule grants the seat user the USB device node so
#     no root is involved in lighting control.
#
# EC caveat: sensors reports pwm2 as "mode = pwm" — the board EC drives
# the duty in manual mode itself, so a direct pwm2 write may be fought
# over by the EC's own curve. Whether writes stick is an open
# observation; first use of the DMS plugin's duty slider is the
# experiment. Rollback for both chains is a reboot (the BIOS reclaims
# the fan, and the ENE chip loses RAM fills on power loss).
{ config, lib, pkgs, ... }:
let cfg = config.modules.capabilities.fan-argb;
in {
  options.modules.capabilities.fan-argb.enable =
    lib.mkEnableOption "CPU fan duty and motherboard ARGB control (NCT6798 + ENE 6K7750)";

  config = lib.mkIf cfg.enable {
    # Without this the NCT6798 is invisible after boot — during the
    # 2026-10-26 investigation it was only ever loaded by hand.
    boot.kernelModules = [ "nct6775" ];

    environment.systemPackages = [ pkgs.ene-fanctl ];

    # Seat-user access to the ENE ARGB controller. uaccess grants the
    # active seat user only; 0cf2:7750 is ENE-specific so nothing else
    # can match. Numbered < 70 so the tag is set before 73-seat-late
    # rules apply it.
    services.udev.packages = [
      (pkgs.writeTextDir "lib/udev/rules.d/69-ene-argb.rules" ''
        SUBSYSTEM=="usb", ATTRS{idVendor}=="0cf2", ATTRS{idProduct}=="7750", TAG+="uaccess"
      '')
    ];

    # Privileged write path for fan duty. Transient template unit: the
    # DMS plugin (or anything else) runs `systemctl start fan-set@140`
    # and polkit lets wheel users start exactly this unit without a
    # password. %i is the duty 0-255; the script clamps to >= 64
    # (25%) so no typo or bad slider value can stall the CPU fan.
    systemd.services."fan-set@" = {
      description = "Set CPU fan duty (NCT6798 pwm2)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeShellScript "fan-set" ''
          set -eu
          duty="$1"
          hw=""
          for d in /sys/class/hwmon/hwmon*; do
            if [ "$(cat "$d/name" 2>/dev/null)" = "nct6798" ]; then
              hw="$d"
              break
            fi
          done
          if [ -z "$hw" ]; then
            echo "fan-set: no nct6798 hwmon found (is nct6775 loaded?)" >&2
            exit 1
          fi
          if [ "$duty" = "auto" ]; then
            # Release a manual override: pwm2_enable=5 is the chip's own
            # SmartFan closed loop (temp-driven), the closest thing to
            # handing control back to the board.
            echo 5 > "$hw/pwm2_enable"
            exit 0
          fi
          if ! [[ "$duty" =~ ^[0-9]+$ ]] || [ "$duty" -gt 255 ]; then
            echo "fan-set: duty must be an integer 0-255 or 'auto', got '$duty'" >&2
            exit 1
          fi
          if [ "$duty" -lt 64 ]; then
            duty=64
          fi
          echo 1 > "$hw/pwm2_enable"
          echo "$duty" > "$hw/pwm2"
        ''} %i";
      };
    };

    # Let wheel users start fan-set@*.service (and nothing else)
    # without a password prompt.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units"
            && subject.isInGroup("wheel")
            && action.lookup("unit") != null
            && action.lookup("unit").indexOf("fan-set@") == 0) {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
