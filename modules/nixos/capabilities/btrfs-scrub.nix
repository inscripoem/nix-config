# Monthly filesystem-level integrity check for btrfs hosts.
#
# Rationale: on single-data btrfs layouts (no RAID1 mirroring), the csum
# verify in a scrub is the ONLY early detector for silent bitrot — without
# it, a corrupt block surfaces only when an application reads it, at which
# point there is no local good copy to repair from. briefcase measured cost:
# 308 GiB scrubbed in 3m12s (2026-10-31 baseline, crc32c hardware accel),
# pure reads, zero wear impact.
#
# Opt-in by design — hosts without a btrfs root (vm, nutshell WSL, air) must
# not pull in a scrub timer for filesystems they do not have.

{ config, lib, ... }:
let cfg = config.modules.capabilities.btrfs-scrub;
in {
  options.modules.capabilities.btrfs-scrub = {
    enable = lib.mkEnableOption "monthly btrfs autoscrub (filesystem-level bitrot detection)";
    # "/" scrubs every subvolume on the root filesystem; additional standalone
    # data filesystems (e.g. briefcase's /games) are listed explicitly.
    fileSystems = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/" ];
      description = "Mountpoints whose backing filesystems get scrubbed.";
    };
  };
  config = lib.mkIf cfg.enable {
    services.btrfs.autoScrub = {
      enable = true;
      interval = "monthly";
      inherit (cfg) fileSystems;
    };
  };
}
