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
#   4. Atom x5-Z8350 CPU cannot handle ANY systemd seccomp/namespace
#      hardening. Services with aggressive serviceConfig all fail to
#      spawn with "Failed to spawn: Operation not permitted".
#      Applied to: avahi-daemon, wpa_supplicant, systemd-logind, nscd.

{ config, lib, pkgs, ... }:

let
  # The Atom x5-Z8350 CPU cannot handle the namespace/seccomp-dependent
  # systemd hardening options that NixOS applies by default.  Disabling
  # all of them is the safe route — on this hardware, a service either
  # works with zero hardening, or it doesn't start at all.
  #
  # Applied to: avahi-daemon, wpa_supplicant, systemd-logind, nscd
  atomSeccompFix = {
    RestrictNamespaces = lib.mkForce false;
    PrivateDevices = lib.mkForce false;
    PrivateTmp = lib.mkForce false;
    NoNewPrivileges = lib.mkForce false;
    ProtectSystem = lib.mkForce false;
    ProtectHome = lib.mkForce false;
    ProtectProc = lib.mkForce "default";
    MemoryDenyWriteExecute = lib.mkForce false;
    SystemCallFilter = lib.mkForce "";
    DevicePolicy = lib.mkForce "auto";
    LockPersonality = lib.mkForce false;
    RestrictRealtime = lib.mkForce false;
    RestrictSUIDSGID = lib.mkForce false;
    ProtectClock = lib.mkForce false;
    ProtectControlGroups = lib.mkForce false;
    ProtectHostname = lib.mkForce false;
    ProtectKernelLogs = lib.mkForce false;
    ProtectKernelModules = lib.mkForce false;
    ProtectKernelTunables = lib.mkForce false;
    ProcSubset = lib.mkForce "all";
    RestrictAddressFamilies = lib.mkForce "AF_UNIX AF_INET AF_INET6 AF_NETLINK";
  };

  atomSeccompFixWpa = atomSeccompFix // {
    RootDirectory = lib.mkForce "";
    RootDirectoryStartOnly = lib.mkForce false;
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

  # ── Atom seccomp fixes ─────────────────────────────────────────
  # mkIf ensures our overrides are evaluated AFTER their respective NixOS modules.

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