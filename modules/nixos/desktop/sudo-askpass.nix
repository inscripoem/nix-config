{ pkgs, ... }:

{
  # Wheel runs sudo without a password: remote agents (ZCode/OpenCode) drive
  # sudo non-interactively, and the GTK askpass dialog on the physical display
  # would stall them. The askpass helper below stays as a fallback in case
  # this rule is ever reverted.
  security.sudo.wheelNeedsPassword = false;
  environment.systemPackages = [ pkgs.openssh-askpass ];

  environment.etc."sudo.conf".text = ''
    Path askpass ${pkgs.openssh-askpass}/libexec/gtk-ssh-askpass
  '';
}
