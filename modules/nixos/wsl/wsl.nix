{ lib, vars, inputs, ... }:

{
  imports = [
    inputs.nixos-wsl.nixosModules.default
  ];

  wsl.enable = true;
  wsl.defaultUser = vars.username;
  wsl.startMenuLaunchers = true;

  networking.networkmanager.enable = lib.mkForce false;
}
