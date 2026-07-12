{ config, lib, ... }:
let cfg = config.modules.capabilities.remote-build-client;
in {
  options.modules.capabilities.remote-build-client.enable =
    lib.mkEnableOption "distribute Nix builds to vars.builders";
  config = lib.mkIf cfg.enable {
    # P2: nix.distributedBuilds, nix.buildMachines, max-jobs = 0
  };
}
