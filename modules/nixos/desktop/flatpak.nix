{ ... }:
{
  services.flatpak = {
    enable = true;
    remotes = [
      { name = "flathub"; location = "https://flathub.org/repo/flathub.flatpakrepo"; }
      { name = "mixtapes"; location = "https://m-obeid.github.io/Mixtapes/mixtapes.flatpakrepo"; }
    ];
    packages = [
      { appId = "com.pocoguy.Muse"; origin = "mixtapes"; }
    ];
    update.onActivation = true;
    # Flatpak's GNetworkMonitorPortal incorrectly reports network as
    # unavailable on NixOS (portal reports available=true, connectivity=4,
    # but GNetworkMonitorPortal inside the sandbox reads available=false,
    # connectivity=1). This breaks all GTK4/WebKitGTK/soup image loading
    # (YouTube thumbnails, login page). Fall back to GNetworkMonitorBase
    # which queries NetworkManager directly via D-Bus.
    overrides = {
      "com.pocoguy.Muse".Environment.GIO_USE_NETWORK_MONITOR = "base";
    };
  };
}
