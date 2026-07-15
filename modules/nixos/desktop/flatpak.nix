{ pkgs, ... }:
{
  services.flatpak = {
    enable = true;
    uninstallUnmanaged = true;
    remotes = [
      { name = "flathub"; location = "https://flathub.org/repo/flathub.flatpakrepo"; }
    ];
    update.onActivation = true;
  };

  # Refresh desktop entries and icon caches after nix-flatpak installs/removes
  # Flatpak apps, so the application menu picks them up without rebooting.
  systemd.services.flatpak-refresh-desktop = {
    after = [ "flatpak-managed-install.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "flatpak-refresh-desktop" ''
        export PATH="${pkgs.lib.makeBinPath [ pkgs.desktop-file-utils pkgs.gtk3 ]}:$PATH"
        update-desktop-database /var/lib/flatpak/exports/share/applications
        for dir in /var/lib/flatpak/exports/share/icons/hicolor; do
          if [ -d "$dir" ]; then
            gtk-update-icon-cache -f -t "$dir" 2>/dev/null || true
          fi
        done
      '';
    };
  };
}
