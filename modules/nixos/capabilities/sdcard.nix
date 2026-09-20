# SD-card wear-mitigation knobs. See docs/wyse3040-install.md.
#
# Two goals:
#   1. Keep writes off the SD as much as possible (tmpfs /tmp, zram
#      before disk swap, aggressive GC).
#   2. When writes must happen, make them TRIM-friendly.

{ config, lib, ... }:
let cfg = config.modules.capabilities.sdcard;
in {
  options.modules.capabilities.sdcard.enable =
    lib.mkEnableOption "SD/eMMC wear mitigation (tmpfs, zram, GC, fstrim)";
  config = lib.mkIf cfg.enable {
    # Periodic GC: actually run `nix-store --gc` weekly. `nh clean`
    # only removes old generation symlinks — it does NOT reclaim
    # orphaned store paths, so without this the SD fills up with
    # unreferenced closures over time.
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };

    # Reactive GC: free space in the Nix store when it dips below 500 MB;
    # keep freeing until 1 GB is available.
    nix.settings.min-free = toString (500 * 1024 * 1024);
    nix.settings.max-free = toString (1024 * 1024 * 1024);

    # Disable nh clean to avoid conflict with nix.gc.automatic above.
    programs.nh.clean.enable = lib.mkForce false;

    # Deduplicate identical store paths via hardlinks; run nightly to
    # avoid contending with typical daytime activity.
    nix.settings.auto-optimise-store = true;
    nix.optimise = {
      automatic = true;
      dates = [ "04:00" ];
    };

    # /tmp in RAM — build artefacts and shell scratch never touch SD.
    boot.tmp.useTmpfs = true;
    boot.tmp.tmpfsSize = "40%";
    boot.tmp.cleanOnBoot = true;

    # zstd-compressed RAM swap first; the on-disk swapfile is the last
    # resort defined in disk-config.nix.
    zramSwap = {
      enable = true;
      memoryPercent = 50;
      algorithm = "zstd";
    };

    # Default swappiness (60) aggressively swaps to SD when zram fills up,
    # killing the card. 10 keeps swapping as true last-resort behavior.
    boot.kernel.sysctl."vm.swappiness" = 10;

    # Cap journal size; a runaway service should not fill the SD.
    services.journald.settings.Journal = {
      SystemMaxUse = "100M";
      RuntimeMaxUse = "50M";
    };

    # Weekly TRIM.
    services.fstrim = {
      enable = true;
      interval = "weekly";
    };

    # Drop docs (~200 MB): headless server never reads them locally.
    documentation.enable = false;
    documentation.nixos.enable = false;
    programs.command-not-found.enable = false;
  };
}
