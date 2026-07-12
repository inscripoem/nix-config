{ config, lib, pkgs, inputs, ... }:
let cfg = config.modules.capabilities.deploy-tools;
in {
  options.modules.capabilities.deploy-tools.enable =
    lib.mkEnableOption "deployment CLIs (colmena, deploy-rs)";
  config = lib.mkIf cfg.enable {
    # P2: environment.systemPackages with colmena + deploy-rs
  };
}
