{ pkgs, vars, ... }:

{
  users.users.${vars.username} = {
    isNormalUser = true;
    description = vars.fullName;
    # systemd --user manager runs from boot and survives logout, so the
    # hermes-gateway user service starts without a login session.
    linger = true;
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      "render"
      "uinput"
      "dialout"
    ];
    openssh.authorizedKeys.keys = vars.sshKeys;
    shell = pkgs.zsh;
  };

  users.users.root.openssh.authorizedKeys.keys = vars.sshKeys;
}
