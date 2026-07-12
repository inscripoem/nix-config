# Disko layout for wyse3040.
#
# Rationale (see docs/wyse3040-install.md §2.1):
#   - eMMC is soldered and prone to failure. Keep it read-heavy: ESP
#     only, remainder unpartitioned as an emergency reserve.
#   - SD card is swappable. Route all writes here: single Btrfs
#     partition with subvolumes for impermanence.
#
# Device identification uses /dev/disk/by-id/ symlinks — the product
# name + serial that udev exports for each mmc device. Reasons:
#   - /dev/mmcblkN is kernel-enumeration order and drifts across
#     kernels (Debian 5.10 had eMMC=blk0/SD=blk1 on this unit;
#     nixos-installer 6.18 has them swapped). Hard-coding mmcblkN
#     would silently wipe the wrong disk on a re-install.
#   - by-id is tied to the physical card. If the SD card is later
#     replaced (it's a wear part), update the sd.device string once
#     and re-run install-remote — this manual edit doubles as a
#     record that the wear-part was swapped.
#
# Confirmed on the current unit (2026-07-11):
#   - eMMC (8 GB, has mmc*boot0/boot1 hardware boot areas)
#       → /dev/disk/by-id/mmc-H8G4a__0x4fa1ec64
#   - SD (32 GB, replacement card after the original SU32G developed
#     SDHCI IRQ storms and forced a btrfs ro-remount mid-install):
#       → /dev/disk/by-id/mmc-SDABC_0xaa000150
# Re-list `ls /dev/disk/by-id/` after any hardware swap.
#
# Subvolume roles:
#   @root       — the ephemeral root; wiped on every boot (see
#                 impermanence.nix), snapshot restored from @root-blank.
#   @root-blank — the "clean slate" readonly snapshot; disko creates
#                 it as an empty subvol, impermanence.nix self-heals
#                 it into a snapshot of @root on first boot.
#   @nix        — the Nix store; zstd compression saves ~30-50% of space.
#   @persist    — the whitelist target; anything under /persist survives
#                 a boot cycle. neededForBoot so initrd sees it.
#   @swap       — 1 GB swapfile as an out-of-memory backstop; primary
#                 swap is zram.
#
# Mount options applied to every subvolume:
#   compress=zstd:3  — cuts SD write volume 30-50%
#   noatime          — skip access-time bookkeeping writes
#   commit=120       — coalesce commits every 120s (default 30s)
#   discard=async    — async TRIM; extends SD lifespan

{
  disko.devices = {
    disk = {
      emmc = {
        type = "disk";
        device = "/dev/disk/by-id/mmc-H8G4a__0x4fa1ec64";
        content = {
          type = "gpt";
          partitions.ESP = {
            size = "512M";
            type = "EF00";
            priority = 1;
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          # eMMC remainder intentionally unpartitioned — preserves wear budget.
        };
      };

      sd = {
        type = "disk";
        device = "/dev/disk/by-id/mmc-SDABC_0xaa000150";
        content = {
          type = "gpt";
          partitions.root = {
            size = "100%";
            content = {
              type = "btrfs";
              # -L nixos: the impermanence rollback script mounts by
              # this label; changing it here means changing that too.
              extraArgs = [ "-f" "-L" "nixos" ];
              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  mountOptions = [ "compress=zstd:3" "noatime" "commit=120" "discard=async" ];
                };
                "@root-blank" = { };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = [ "compress=zstd:3" "noatime" "commit=120" "discard=async" ];
                };
                "@persist" = {
                  mountpoint = "/persist";
                  mountOptions = [ "compress=zstd:3" "noatime" "commit=120" "discard=async" ];
                };
                "@swap" = {
                  mountpoint = "/.swapvol";
                  swap.swapfile.size = "1G";
                };
              };
            };
          };
        };
      };
    };
  };

  # /persist must be mounted before impermanence's user activation runs.
  fileSystems."/persist".neededForBoot = true;
}
