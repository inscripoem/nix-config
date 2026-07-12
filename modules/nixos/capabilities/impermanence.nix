{ config, lib, ... }:
let cfg = config.modules.capabilities.impermanence;
in {
  options.modules.capabilities.impermanence.enable =
    lib.mkEnableOption "ephemeral root + /persist whitelist";
  config = lib.mkIf cfg.enable {
    # P2: impermanence module, rollback service, persistence paths
  };
}
