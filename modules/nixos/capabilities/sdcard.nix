{ config, lib, ... }:
let cfg = config.modules.capabilities.sdcard;
in {
  options.modules.capabilities.sdcard.enable =
    lib.mkEnableOption "SD/eMMC wear mitigation (tmpfs, zram, GC, fstrim)";
  config = lib.mkIf cfg.enable {
    # P2: nix.gc, zramSwap, tmpfs /tmp, fstrim, journald cap
  };
}
