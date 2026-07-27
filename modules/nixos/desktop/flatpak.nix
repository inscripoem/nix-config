{ pkgs, ... }:

{
  services.flatpak = {
    enable = true;
    uninstallUnmanaged = true;
    remotes = [
      { name = "flathub"; location = "https://flathub.org/repo/flathub.flatpakrepo"; }
    ];
    packages = [
      "com.usebottles.bottles"
    ];
    update.onActivation = true;
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
