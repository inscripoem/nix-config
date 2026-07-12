# X11 forwarding for the desktop class.
# Enables `ssh -X` for GUI hosts so remote X clients can display
# locally.
{ ... }:
{
  services.openssh.settings.X11Forwarding = true;
}
