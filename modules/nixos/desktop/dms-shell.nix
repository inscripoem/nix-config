{ lib, pkgs, ... }:

let
  hxrebornPluginsSrc = pkgs.fetchFromGitHub {
    owner = "hxreborn";
    repo = "dms-plugins";
    rev = "7e3ade68c2d04ae3a0dff42b69357ae3e03d0732";
    hash = "sha256-+mgtyRStSE75f0e5uH2+6WDm1YeY/zIG3OFF73bYAf8=";
  };
  # Single source of truth for the plugin's version: bumping plugin.json
  # updates the derivation name too, so generation diffs render bumps as
  # plain version changes.
  onedriveSyncManifest = lib.importJSON ./dms-plugins/onedrive-sync/plugin.json;
in
{
  # Enable DankMaterialShell - desktop shell for niri.
  # NOTE: systemd.enable is intentionally false. The upstream module would
  # bind dms.service to graphical-session.target, which is also activated by
  # KDE Plasma sessions, causing the niri taskbar to appear on
  # top of those desktops. We start dms from niri's spawn-at-startup
  # instead (see home/desktop/niri.nix) so it only runs inside niri.
  programs.dms-shell = {
    enable = true;
    systemd.enable = false;

    plugins = {
      tailscale = {
        enable = true;
        src = "${hxrebornPluginsSrc}/dms-tailscale-manager";
      };
      screenRecorder = {
        enable = true;
        src = "${hxrebornPluginsSrc}/dms-screen-recorder";
      };

      # In-repo plugin: OneDrive sync status pill (see dms-plugins/onedrive-sync).
      # The widget's onedrive binary reference is substituted to an absolute
      # store path at build time: the DMS session PATH does not reliably
      # carry the per-user profile bin dir, so PATH lookup is not safe.
      onedriveSync = {
        enable = true;
        src = pkgs.runCommand "dms-plugin-onedrive-sync-${onedriveSyncManifest.version}" { } ''
          mkdir -p $out
          cp -r ${./dms-plugins/onedrive-sync}/. $out/
          substituteInPlace $out/OneDriveWidget.qml \
            --replace '@onedrive@' '${pkgs.onedrive}/bin/onedrive'
        '';
      };
    };
  };

  # Required by the Screen Recorder DMS plugin
  environment.systemPackages = [ pkgs.gpu-screen-recorder ];
}