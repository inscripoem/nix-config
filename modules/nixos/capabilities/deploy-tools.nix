{ config, lib, pkgs, inputs, ... }:
let cfg = config.modules.capabilities.deploy-tools;
in {
  options.modules.capabilities.deploy-tools.enable =
    lib.mkEnableOption "deployment CLIs (colmena, deploy-rs)";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena
      inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.deploy-rs
    ];
  };
}
