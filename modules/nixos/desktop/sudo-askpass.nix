{ pkgs, ... }:

{
  # GTK3 graphical password dialog for sudo, works on both X11 and Wayland.
  # Allows non-interactive callers (including OpenCode toolcalls) to prompt for
  # the sudo password via a GUI popup instead of failing on a missing TTY.
  environment.systemPackages = [ pkgs.openssh-askpass ];

  environment.etc."sudo.conf".text = ''
    Path askpass ${pkgs.openssh-askpass}/libexec/gtk-ssh-askpass
  '';
}
