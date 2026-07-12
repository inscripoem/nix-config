# System-side "remote nix build worker" role.
#
# Any host importing this module becomes a remote builder: an unprivileged
# `nix-builder` user with the Nix trust flag, accepting SSH connections
# authorised by vars.builderClientKeys.
#
# Client-side consumption lives in hosts/<name>/remote-build.nix, which
# maps vars.builders entries into nix.buildMachines records.

{ vars, ... }:

{
  users.users.nix-builder = {
    isNormalUser = true;
    description = "Remote nix build worker";
    openssh.authorizedKeys.keys = vars.builderClientKeys or [ ];
  };
  nix.settings.trusted-users = [ "nix-builder" ];
}
