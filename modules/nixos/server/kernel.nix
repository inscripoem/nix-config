{ lib, pkgs, ... }:
{
  # Stable kernel for server workloads — overrides the base default
  # (linuxPackages_latest). Set as mkDefault so a specific host
  # hardware config can still force a different kernel if needed.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

  # Less aggressive panic timeout than the desktop base default.
  # Server uptime matters more than crash forensics.
  boot.kernel.sysctl = {
    "kernel.panic" = 60;
  };
}
