{ pkgs, ... }:
{
  # Stable kernel for server workloads. Plain assignment outranks the base
  # module's mkDefault (linuxPackages_latest), while a specific host can
  # still use mkForce to pin a different kernel if needed.
  boot.kernelPackages = pkgs.linuxPackages;

  # Less aggressive panic timeout than the desktop base default.
  # Server uptime matters more than crash forensics.
  boot.kernel.sysctl = {
    "kernel.panic" = 60;
  };
}
