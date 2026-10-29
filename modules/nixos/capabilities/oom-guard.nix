# OOM policy: zram-first swap with earlyoom as the single OOM authority.
#
# Swap layout: zram (zstd-compressed, 50% of RAM) is the primary swap and
# the on-disk swapfile (per-host disk-config.nix) is the backstop. The
# default zram priority (5) sits above disk swap, so zram fills first.
# vm.page-cluster=0 disables read-ahead clustering: it only pays off on
# seek-y disk swap, and on a RAM-backed device it just wastes memory.
#
# earlyoom SIGTERMs the largest process when available memory AND free
# swap both fall below 10% (SIGKILL at 5%), converting memory exhaustion
# from a watchdog-panic reboot (2026-10-16 full-core nix build on
# briefcase) into killing the culprit; kills land in journalctl -u
# earlyoom. systemd-oomd ships enabled but monitors no slices by default,
# so it guards nothing out of the box; it is disabled here so earlyoom
# stays the single OOM authority.
#
# Opt-in by design — never make this a server-class default. A server
# silently killing processes is a hard taboo; each host must enable it
# explicitly.
#
# Relation to capabilities/sdcard.nix: that module carries the same
# zram-first strategy inside the SD-card wear-mitigation bundle. The two
# are independent implementations and the duplication is intentional:
# this is the generic OOM guard, that one is scoped to wear mitigation.

{ config, lib, ... }:
let cfg = config.modules.capabilities.oom-guard;
in {
  options.modules.capabilities.oom-guard.enable =
    lib.mkEnableOption "zram-first swap and earlyoom OOM guard (single OOM authority)";
  config = lib.mkIf cfg.enable {
    # zram as primary swap; disk swap is the backstop.
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 50;
    };

    # Read-ahead clustering only pays off on seek-y disk swap; on a
    # RAM-backed device it just wastes memory.
    boot.kernel.sysctl."vm.page-cluster" = 0;

    # Single OOM authority: earlyoom in, systemd-oomd out.
    services.earlyoom.enable = true;
    systemd.oomd.enable = false;
  };
}
