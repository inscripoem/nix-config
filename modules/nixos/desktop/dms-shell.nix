{ pkgs, ... }:

let
  hxrebornPluginsSrc = pkgs.fetchFromGitHub {
    owner = "hxreborn";
    repo = "dms-plugins";
    rev = "7e3ade68c2d04ae3a0dff42b69357ae3e03d0732";
    hash = "sha256-+mgtyRStSE75f0e5uH2+6WDm1YeY/zIG3OFF73bYAf8=";
  };
in
{
  # Enable DankMaterialShell - desktop shell for niri.
  # NOTE: systemd.enable is intentionally false. The upstream module would
  # bind dms.service to graphical-session.target, which is also activated by
  # KDE Plasma and COSMIC sessions, causing the niri taskbar to appear on
  # top of those desktops. We start dms from niri's spawn-at-startup
  # instead (see home/desktop/niri.nix) so it only runs inside niri.
  programs.dms-shell = {
    enable = true;
    systemd.enable = false;
    enableSystemMonitoring = true;
    enableDynamicTheming = true;

    plugins = {
      tailscale = {
        enable = true;
        src = "${hxrebornPluginsSrc}/dms-tailscale-manager";
      };
      screenRecorder = {
        enable = true;
        src = "${hxrebornPluginsSrc}/dms-screen-recorder";
      };
    };
  };

  # Required by the Screen Recorder DMS plugin
  environment.systemPackages = [ pkgs.gpu-screen-recorder ];
}