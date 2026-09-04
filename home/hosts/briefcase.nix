{
  imports = [ ../desktop.nix ];

  packs.ai.enable = true;
  packs.creative.enable = true;
  packs.gaming.enable = true;
  packs.toolchain.enable = true;

  # Uninstall trae-cn on briefcase only; vm keeps trae-cn.
  desktop.editors-gui.traeCn.enable = false;
}
