# System-side "remote nix build worker" role.
#
# Any host enabling this capability becomes a remote builder: an
# unprivileged `nix-builder` user with the Nix trust flag, accepting
# SSH connections authorised by vars.builderClientKeys.
#
# Client-side consumption lives in the remote-build-client capability,
# which maps vars.builders entries into nix.buildMachines records.

{ config, lib, vars, ... }:
let cfg = config.modules.capabilities.remote-builder;
in {
  options.modules.capabilities.remote-builder.enable =
    lib.mkEnableOption "remote Nix build worker (accepts SSH builds)";
  config = lib.mkIf cfg.enable {
    users.users.nix-builder = {
      isNormalUser = true;
      description = "Remote nix build worker";
      openssh.authorizedKeys.keys = vars.builderClientKeys or [ ];
    };
    nix.settings.trusted-users = [ "nix-builder" ];
  };
}
