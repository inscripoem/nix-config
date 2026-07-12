{ config, lib, ... }:
let cfg = config.modules.capabilities.docker;
in {
  options.modules.capabilities.docker.enable =
    lib.mkEnableOption "Docker daemon, docker-compose, docker group";
  config = lib.mkIf cfg.enable {
    # P2: virtualisation.docker, persistence of /var/lib/docker
  };
}
