# Impermanence for wyse3040.
#
# On every boot, initrd deletes @root and takes a fresh snapshot of
# @root-blank into its place, so / is always in a "just installed"
# state. The whitelist below (mounted from @persist) is bind-mounted
# back on top so declared paths survive the wipe.
#
# Self-healing: disko creates @root-blank as an empty subvolume, not
# as a snapshot. On first boot we detect this (a real snapshot is
# read-only AND has a non-zero Parent UUID) and rebuild @root-blank as
# a read-only snapshot of the freshly-installed @root. From then on
# the regular rollback loop just works.
#
# Implementation notes:
#   - Uses systemd-initrd (boot.initrd.systemd.enable). The classic
#     boot.initrd.postDeviceCommands hook fires before udev has
#     populated /dev/disk/by-label/*, so the first mount attempt races
#     the SD card enumeration. A systemd unit with an explicit
#     After/Requires on the .device unit removes that race.
#   - DefaultDependencies=no is required to avoid the implicit
#     sysinit.target -> ... -> sysroot.mount ordering cycle that
#     systemd would otherwise break by dropping this service.
#   - The `-` in the label "nixos" needs no escaping, but the same
#     device path with `-` in it would need `\x2d` escaping in unit
#     names.
#
# See docs/wyse3040-install.md §2.2 and §2.5 for the design.

{ inputs, vars, pkgs, ... }:

{
  imports = [ inputs.impermanence.nixosModules.impermanence ];

  boot.initrd.systemd.enable = true;

  # Unauthenticated emergency shell on TTY1 if any critical initrd unit
  # fails (e.g. rollback.service timing out, sysroot.mount failing).
  # wyse3040 is physically secured; anyone with local access could just
  # pull the SD card. The safety net is worth it while the systemd
  # initrd migration is fresh — flip back to `false` once rollback has
  # proven stable across a few reboots.
  boot.initrd.systemd.emergencyAccess = true;

  # Ensure btrfs userspace is available inside initrd. storePaths puts
  # the binary in initramfs; initrdBin puts it on PATH.
  boot.initrd.systemd.initrdBin = [ pkgs.btrfs-progs ];

  boot.initrd.systemd.services.rollback = {
    description = "Rollback btrfs @root to a pristine @root-blank snapshot";
    wantedBy = [ "initrd.target" ];
    after = [ "dev-disk-by\\x2dlabel-nixos.device" ];
    requires = [ "dev-disk-by\\x2dlabel-nixos.device" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig = {
      Type = "oneshot";
      # Deleting a large @root can take a while on slow SD cards.
      TimeoutStartSec = "2min";
    };
    script = ''
      mkdir -p /btrfs_tmp
      mount -t btrfs -o subvol=/ /dev/disk/by-label/nixos /btrfs_tmp

      # First-boot self-heal: a real read-only snapshot has ro=true
      # AND a non-zero Parent UUID. disko's empty subvol has neither.
      needs_heal=0
      if ! btrfs property get -ts /btrfs_tmp/@root-blank ro 2>/dev/null | grep -q 'ro=true'; then
        needs_heal=1
      fi
      if btrfs subvolume show /btrfs_tmp/@root-blank 2>/dev/null | grep -qE 'Parent UUID:[[:space:]]*-'; then
        needs_heal=1
      fi
      if [ "$needs_heal" = 1 ]; then
        btrfs subvolume delete /btrfs_tmp/@root-blank || true
        btrfs subvolume snapshot -r /btrfs_tmp/@root /btrfs_tmp/@root-blank
      fi

      # Delete nested subvolumes under @root (e.g. /var/lib/portables,
      # /var/lib/machines, /var/tmp that systemd auto-creates) before
      # deleting @root itself.
      btrfs subvolume list -o /btrfs_tmp/@root | cut -f9- -d' ' | while read s; do
        btrfs subvolume delete "/btrfs_tmp/$s"
      done
      btrfs subvolume delete /btrfs_tmp/@root
      btrfs subvolume snapshot /btrfs_tmp/@root-blank /btrfs_tmp/@root
      umount /btrfs_tmp
    '';
  };

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      # System bookkeeping that must survive reboots.
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd"
      "/var/lib/NetworkManager"
      "/etc/NetworkManager/system-connections"
      "/var/lib/sops-nix"

      # Hand-managed runtime area (imperative tier). Compose files, DB
      # volumes, hand-tweaked configs live here. See install doc §2.5.
      "/srv"

      # Reserved for oci-containers state if compose files are ever
      # promoted into declarative Nix modules (semi-declarative tier).
      "/var/lib/services"
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
    users.${vars.username} = {
      directories = [
        "Projects"
        { directory = ".ssh"; mode = "0700"; }
        { directory = ".gnupg"; mode = "0700"; }
        # ~/.cache covers uv / cargo / pip / npm / nix eval cache.
        ".cache"
        # ~/.local/share covers direnv / atuin / pnpm / git-cliff etc.
        ".local/share"
        ".local/state"
        # NOTE: ~/.config is intentionally NOT persisted — home-manager
        # regenerates it declaratively on every activation.
      ];
      files = [ ".zsh_history" ];
    };
  };
}
