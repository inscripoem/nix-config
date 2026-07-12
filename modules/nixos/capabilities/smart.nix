{ config, lib, ... }:
let cfg = config.modules.capabilities.smart;
in {
  options.modules.capabilities.smart.enable =
    lib.mkEnableOption "disk health surveillance (smartmontools, nvme-cli)";
  config = lib.mkIf cfg.enable {
    # P2: services.smartd, environment.systemPackages smartmontools/nvme-cli
  };
}
