{ pkgs, ... }:

{
  # KDE Plasma graphical password dialog for sudo, works on both X11 and Wayland.
  # Allows non-interactive callers (including OpenCode toolcalls) to prompt for
  # the sudo password via a GUI popup instead of failing on a missing TTY.
  environment.systemPackages = [ pkgs.kdePackages.ksshaskpass ];

  environment.etc."sudo.conf".text = ''
    Path askpass ${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass
  '';
}
