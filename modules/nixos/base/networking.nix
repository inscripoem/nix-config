{ lib, ... }:
{
  networking.networkmanager.enable = lib.mkDefault true;
}
