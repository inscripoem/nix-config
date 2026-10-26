# Desktop-only applications that have no reason to exist on headless hosts.

{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    kdePackages.kate
    papirus-icon-theme
    tela-circle-icon-theme
    colloid-icon-theme
    # Expose GLib GSettings schemas (org.gnome.desktop.interface etc.) so the
    # GDK Wayland GSettings binding activates. DMS writes
    # `gsettings set org.gnome.desktop.interface icon-theme` on theme switch,
    # but it silently fails without schemas — with them, Qt/GTK apps receive
    # realtime icon-theme updates.
    gsettings-desktop-schemas
  ];
}
