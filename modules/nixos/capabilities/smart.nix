{ config, lib, pkgs, ... }:
let cfg = config.modules.capabilities.smart;
in {
  options.modules.capabilities.smart.enable =
    lib.mkEnableOption "disk health surveillance (smartmontools, nvme-cli)";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.smartmontools
      pkgs.nvme-cli
    ];
    services.smartd = {
      enable = true;
      autodetect = true;
      defaults.autodetected = "-a -o on -S on -n standby,q -s (S/../.././02|L/../../6/03) -W 4,60,75";
      notifications.wall.enable = true;
    };
  };
}
