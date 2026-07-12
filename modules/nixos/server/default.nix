{ config, lib, pkgs, ... }:
{
  imports = [
    ./kernel.nix
  ];

  # Stable kernel for server workloads — overrides the base default
  # (linuxPackages_latest). Set here as mkDefault so a specific host
  # hardware config can still force a different kernel if needed.
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages;
}
