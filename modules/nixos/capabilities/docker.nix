{ config, lib, vars, ... }:
let
  cfg = config.modules.capabilities.docker;
  impCfg = config.modules.capabilities.impermanence;
in {
  options.modules.capabilities.docker.enable =
    lib.mkEnableOption "Docker daemon, docker-compose, docker group";
  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;
    users.users.${vars.username}.extraGroups = [ "docker" ];

    # Persist Docker state across ephemeral-root reboots.
    environment.persistence."/persist" = lib.mkIf impCfg.enable {
      directories = [ "/var/lib/docker" ];
    };
  };
}
