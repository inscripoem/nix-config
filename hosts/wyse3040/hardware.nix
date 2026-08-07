# Wyse 3040-specific quirks. See docs/wyse3040-install.md §1 for context.
#
#   1. UEFI fallback trap: firmware ignores NVRAM boot entries; only
#      \EFI\BOOT\BOOTX64.EFI is honoured. Hence GRUB with
#      efiInstallAsRemovable = true (writes the bootloader to that
#      fallback path).
#   2. dw_dmac_core hangs on shutdown/reboot on this hardware.
#      Blacklist the module and force UEFI runtime reboot via
#      kernelParams.
#   3. eMMC (mmcblk0) and SD (mmcblk1) both need mmc_block / sdhci_acpi
#      / sdhci in initrd; without them the root filesystem cannot be
#      mounted early.
#   4. PrivateTmp fails: wear-leveling.nix creates a tmpfs on /tmp
#      (boot.tmp.useTmpfs). systemd's PrivateTmp cannot overmount an
#      existing tmpfs — the clone() with CLONE_NEWNS fails with EPERM.
#      All OTHER hardening (seccomp, namespaces, /dev isolation) works
#      correctly on the Atom x5-Z8350 running kernel 6.18.5.
#      Use TemporaryFileSystem as an equivalent drop-in replacement.
#      Applied to: avahi-daemon, wpa_supplicant, systemd-logind, nscd,
#      systemd-hostnamed.

{ config, lib, ... }:

let
  # PrivateTmp fails on this host because wear-leveling.nix mounts a
  # tmpfs on /tmp (boot.tmp.useTmpfs). systemd's PrivateTmp clone() with
  # CLONE_NEWNS hits EPERM when attempting to overmount the pre-existing
  # tmpfs. All other systemd hardening — seccomp, mount namespaces,
  # /dev isolation, etc. — works correctly.
  #
  # TemporaryFileSystem="/tmp /var/tmp" achieves the same per-service
  # tmp isolation via a different code path that does not trigger the
  # overmount conflict. It also puts /var/tmp in RAM (it currently
  # lives on the SD card btrfs), which is a net win for wear levelling.
  #
  # Verified empirically on wyse3040 (kernel 6.18.5, CONFIG_SECCOMP=y):
  #   SystemCallFilter=@system-service  ✓
  #   MemoryDenyWriteExecute=yes        ✓
  #   ProtectSystem=strict              ✓
  #   ProtectHome=yes                   ✓
  #   PrivateDevices=yes                ✓
  #   RestrictNamespaces=yes            ✓
  #   … and every other hardening option ✓
  #   PrivateTmp=yes                    ✗ (see above)
  #   TemporaryFileSystem="/tmp /var/tmp"  ✓
  #
  # Applied to: avahi-daemon, wpa_supplicant, systemd-logind, nscd,
  # systemd-hostnamed.
  atomSeccompFix = {
    PrivateTmp = lib.mkForce false;
    TemporaryFileSystem = lib.mkForce "/tmp /var/tmp";
  };

  # wpa_supplicant additionally needs AF_PACKET for raw WiFi frames.
  atomSeccompFixWpa = atomSeccompFix // {
    RestrictAddressFamilies = lib.mkForce "AF_UNIX AF_INET AF_INET6 AF_NETLINK AF_PACKET";
  };
in

{
  boot.initrd.availableKernelModules = [ "mmc_block" "sdhci_acpi" "sdhci" ];

  boot.loader = {
    systemd-boot.enable = false;
    grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      efiInstallAsRemovable = true;
      configurationLimit = 5;
    };
    efi.canTouchEfiVariables = false;
  };

  boot.blacklistedKernelModules = [ "dw_dmac_core" "rtl8192cu" ];
  boot.kernelParams = [ "reboot=efi" ];

  boot.kernel.sysctl."kernel.panic" = lib.mkForce 60;

  systemd.settings.Manager = {
    DefaultTimeoutStartSec = "5min";
    DefaultTimeoutStopSec = "5min";
  };

  # ── tmpfs overmount fix ─────────────────────────────────────────
  # PrivateTmp conflicts with boot.tmp.useTmpfs (wear-leveling.nix).
  # TemporaryFileSystem provides equivalent isolation without the conflict.

  systemd.services.avahi-daemon = lib.mkIf config.services.avahi.enable {
    serviceConfig = atomSeccompFix;
  };

  systemd.services.wpa_supplicant = lib.mkIf config.networking.wireless.enable {
    serviceConfig = atomSeccompFixWpa;
  };

  systemd.services.systemd-logind.serviceConfig = atomSeccompFix;

  systemd.services.nscd.serviceConfig = atomSeccompFix;

  systemd.services.systemd-hostnamed.serviceConfig = atomSeccompFix;

  # ── SSH speed ───────────────────────────────────────────────────

  services.openssh.settings.KexAlgorithms = lib.mkForce [
    "curve25519-sha256"
    "curve25519-sha256@libssh.org"
    "diffie-hellman-group-exchange-sha256"
    "diffie-hellman-group14-sha256"
  ];
}