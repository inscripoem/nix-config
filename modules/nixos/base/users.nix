{ config, pkgs, vars, ... }:

{
  users.users.${vars.username} = {
    isNormalUser = true;
    description = vars.fullName;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    openssh.authorizedKeys.keys = vars.sshKeys;
    shell = pkgs.zsh;
  };

  users.users.root.openssh.authorizedKeys.keys = vars.sshKeys;
}
