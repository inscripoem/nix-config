{ config, lib, pkgs, ... }:
{
  # Server kernel strategy.
  # P2: override base kernelPackages to pkgs.linuxPackages (stable LTS)
  # and set a less aggressive panic timeout than the desktop aggressive
  # defaults in modules/nixos/base/kernel.nix.
}
