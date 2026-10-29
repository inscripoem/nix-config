{ vars, inputs, ... }:

{
  imports = [
    inputs.nixos-wsl.nixosModules.default
  ];

  wsl.enable = true;
  wsl.defaultUser = vars.username;
  wsl.startMenuLaunchers = true;

  # Plain assignment is enough to outrank the base module's mkDefault.
  networking.networkmanager.enable = false;
}
