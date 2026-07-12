{ config, lib, ... }:
let cfg = config.modules.capabilities.tailscale;
in {
  options.modules.capabilities.tailscale.enable =
    lib.mkEnableOption "Tailscale daemon";
  config = lib.mkIf cfg.enable {
    # P2: services.tailscale.enable, openFirewall
  };
}
