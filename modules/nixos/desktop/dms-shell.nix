{ config, lib, pkgs, ... }:

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
  argbFansManifest = lib.importJSON ./dms-plugins/argb-fans/plugin.json;
in
{
  # Enable Dux Shell (formerly DankMaterialShell; renamed upstream and in
  # nixpkgs on 2026-10-20 — the `dms` CLI binary and dms.service unit
  # names are unchanged).
  # NOTE: systemd.enable is intentionally false. The upstream module binds
  # dms.service to graphical-session.target, which is also activated by
  # KDE Plasma sessions, causing the niri taskbar to appear on top of those
  # desktops. home/desktop/niri/default.nix instead declares its own dms.service
  # (WantedBy=niri.service, Type=dbus on the StatusNotifierWatcher name) so
  # DMS only runs inside niri sessions and XDG autostart apps can never
  # race its tray watcher.
  programs.dux-shell = {
    enable = true;
    systemd.enable = false;

    plugins = {
      # In-repo fork of hxreborn/dms-tailscale-manager @ 7e3ade6 with local
      # additions: scrollable peer list, account-source filter, funnel
      # ingress filtering (default off) and a Copy DNS Name action.
      # Revert this src line to "${hxrebornPluginsSrc}/dms-tailscale-manager"
      # to fall back to upstream.
      tailscale = {
        enable = true;
        src = "${./dms-plugins/tailscale-manager}";
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

      # In-repo plugin: CPU fan duty + motherboard ARGB control (see
      # dms-plugins/argb-fans). Gated on the fan-argb capability
      # (briefcase hardware: NCT6798 + ENE 6K7750) so other hosts never
      # see the widget. The ene-fanctl reference is substituted to an
      # absolute store path at build time for the same PATH reason as
      # onedrive above.
      argbFans = {
        enable = config.modules.capabilities.fan-argb.enable;
        src = pkgs.runCommand "dms-plugin-argb-fans-${argbFansManifest.version}" { } ''
          mkdir -p $out
          cp -r ${./dms-plugins/argb-fans}/. $out/
          substituteInPlace $out/ArgbFanWidget.qml \
            --replace '@enefanctl@' '${pkgs.ene-fanctl}/bin/ene-fanctl'
        '';
      };
    };
  };

  # Required by the Screen Recorder DMS plugin
  environment.systemPackages = [ pkgs.gpu-screen-recorder ];

  # DMS Spotlight's file provider stays hidden until the dsearch daemon
  # (DankSearch, renamed dux-search in nixpkgs; the service name stays
  # dsearch) is reachable. graphical-session.target keeps it out of
  # headless sessions; the index scope is declared in
  # home/desktop/desktop-env.nix.
  programs.dux-search = {
    enable = true;
    systemd.target = "graphical-session.target";
  };
}