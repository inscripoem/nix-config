{ config, lib, ... }:
let cfg = config.modules.capabilities.remote-builder;
in {
  options.modules.capabilities.remote-builder.enable =
    lib.mkEnableOption "remote Nix build worker (accepts SSH builds)";
  config = lib.mkIf cfg.enable {
    # P2: nix-builder user, trusted-users, authorizedKeys
  };
}
