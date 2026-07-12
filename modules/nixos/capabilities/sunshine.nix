{ config, lib, pkgs, ... }:
let cfg = config.modules.capabilities.sunshine;
in {
  options.modules.capabilities.sunshine.enable =
    lib.mkEnableOption "Moonlight/Sunshine game streaming";
  config = lib.mkIf cfg.enable {
    # P2: services.sunshine, systemd services, polkit
  };
}
