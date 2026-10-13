{
  imports = [ ../desktop.nix ];

  packs.ai.enable = true;
  # Opt-in extra from packs.ai (defaults to false) — this host only.
  packs.ai.hermes-agent.enable = true;
  packs.ai."qoder-cn".enable = true;
  packs.ai.workbuddy.enable = true;
  packs.ai.orca.enable = true;
  packs.ai.colab.enable = true;
  packs.creative.enable = true;
  packs.gaming.enable = true;
  packs.office.enable = true;
  packs.toolchain.enable = true;

  # Uninstall trae-cn on briefcase only; vm keeps trae-cn.
  desktop.editors-gui.traeCn.enable = false;
}
