# lan-mouse — software KVM (share one keyboard/mouse across machines).
#
# Why lan-mouse (and not Deskflow / Input Leap / Barrier):
#   Those depend on the org.freedesktop.portal.InputCapture portal
#   (server mode) or the RemoteDesktop portal (client mode), neither of
#   which niri implements (niri-wm/niri#823 and #390, both still open
#   as of 2026-10). lan-mouse instead captures input through a
#   layer-shell surface and injects it via wlr-virtual-pointer /
#   virtual-keyboard, both supported by niri, so it works natively on
#   this host.
#
# Firewall: UDP 4242 carries pairing/session traffic. Opened together
# with the package so peers can initiate connections in both
# directions, not just outbound from this host.
#
# No systemd unit: the GUI launches its own daemon when started; run
# it on demand from the app launcher (on-demand services principle).
{ config, lib, pkgs, ... }:
let cfg = config.modules.capabilities.lan-mouse;
in {
  options.modules.capabilities.lan-mouse.enable =
    lib.mkEnableOption "lan-mouse software KVM";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.lan-mouse ];
    networking.firewall.allowedUDPPorts = [ 4242 ];
  };
}
