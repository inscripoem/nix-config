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
  };
}
