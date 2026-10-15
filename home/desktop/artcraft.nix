{
  config,
  lib,
  ...
}:
{
  # Wiring for the packs.creative.photocraft opt-in. Lives in the desktop
  # group, not the pack, because only desktop hosts import the artcraft HM
  # module (desktopHmModules) that declares programs.artcraft.
  programs.artcraft = lib.mkIf config.packs.creative.photocraft.enable {
    enable = true;
    apps = [ "photocraft" ];
  };
}
