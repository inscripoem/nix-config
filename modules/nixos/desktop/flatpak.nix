{ lib, pkgs, ... }:

{
  services.flatpak = {
    enable = true;
    # mkDefault: this uninstalls manually-installed flatpaks on activation,
    # a side-effectful default — keep it overridable by lower layers.
    uninstallUnmanaged = lib.mkDefault true;
    remotes = [
      { name = "flathub"; location = "https://flathub.org/repo/flathub.flatpakrepo"; }
    ];
    packages = [
      "com.baidu.NetDisk"
      "com.usebottles.bottles"
    ];
    update.onActivation = true;
  };

  # nix-flatpak's activation unit only orders After=multi-user.target, which
  # does not imply connectivity: on Wi-Fi the first flathub summary fetch
  # races DNS resolution and fails (every journal failure is "Could not
  # resolve hostname"). Pulling network-online holds the first attempt until
  # NM actually reports a connection.
  systemd.services.flatpak-managed-install = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    # network-online.target only means "was reached once": switching restarts
    # NetworkManager, so this unit can start while DNS/TLS is still down. Any
    # failed unit makes switch-to-configuration exit 4, which aborts the whole
    # switch before the profile is written (seen 2026-11-03). Probe the real
    # endpoint instead: DNS alone does not prove HTTPS works. A timeout fails
    # the unit so Restart=on-failure retries in a minute rather than hanging
    # the switch. Online, the first probe succeeds and costs nothing.
    serviceConfig.ExecStartPre = pkgs.writeShellScript "wait-flathub" ''
      deadline=$((SECONDS + 15))
      while (( SECONDS < deadline )); do
        ${pkgs.curl}/bin/curl -fsS --connect-timeout 1 --max-time 2 -o /dev/null \
          https://dl.flathub.org/repo/flathub.flatpakrepo && exit 0
        ${pkgs.coreutils}/bin/sleep 1
      done
      exit 1
    '';
  };

  # NixOS does not automatically refresh the desktop entry / MIME cache for
  # Flatpak exports. Run update-desktop-database after nix-flatpak activation so
  # launchers and file managers pick up newly installed/removed Flatpak apps
  # without rebooting. See gmodena/nix-flatpak#175.
  system.activationScripts.flatpak-desktop-cache = {
    deps = [ "etc" ];
    text = ''
      ${pkgs.desktop-file-utils}/bin/update-desktop-database /var/lib/flatpak/exports/share/applications
      ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t /var/lib/flatpak/exports/share/icons/hicolor 2>/dev/null || true
    '';
  };
}
