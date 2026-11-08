{ pkgs, ... }:

# GPU profile: AMD Polaris 10 (Radeon Pro WX 5100, PCI ID 0x67c7).
#
# The WX 5100 is a GCN 4 card driven by the in-tree amdgpu driver. Keep the
# display stack on Mesa's modesetting path and expose the radeonsi VA-API
# backend to both the desktop and the Sunshine services.
#
# Do not pin a connector here. The four DisplayPort connectors are enumerated
# by the kernel and can change order when a monitor or dummy plug moves; the
# display and Sunshine configuration therefore discovers the active output
# at runtime.
{
  hardware.graphics.enable = true;

  services.xserver.videoDrivers = [ "modesetting" ];
  boot.initrd.kernelModules = [ "amdgpu" ];

  # Keep the ASPM mitigation used by the hard-freeze experiment. The Intel
  # i915-only parameters live in the retained Arc profile and disappear when
  # that profile is not imported.
  boot.kernelParams = [
    "pcie_aspm=off"
  ];

  environment.sessionVariables.LIBVA_DRIVER_NAME = "radeonsi";

  # Explicit service environments cover the root greeter, which does not
  # inherit the graphical user's session variables.
  systemd.services.sunshine-greeter.environment.LIBVA_DRIVER_NAME = "radeonsi";
  systemd.user.services.sunshine.environment.LIBVA_DRIVER_NAME = "radeonsi";

  environment.systemPackages = with pkgs; [
    libva-utils
    nvtopPackages.amd
    radeontop
  ];
}
