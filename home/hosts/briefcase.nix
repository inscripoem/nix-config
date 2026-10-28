{
  imports = [ ../desktop.nix ];

  packs.ai.enable = true;
  # Opt-in extras from packs.ai (defaults to false) — this host only.
  packs.ai.hermes-agent.enable = true;
  packs.ai.workbuddy.enable = true;
  packs.ai.orca.enable = true;
  packs.ai.orca.autostart = true;
  packs.ai.dsh.enable = true;
  packs.ai.magpie.enable = true;
  packs.ai.cc-switch.enable = true;
  packs.creative.enable = true;
  # Opt-in extra from packs.creative (defaults to false) — this host only.
  packs.creative.photocraft.enable = true;
  packs.gaming.enable = true;
  packs.office.enable = true;
  packs.onedrive.enable = true;
  packs.toolchain.enable = true;

  desktop.emacs.enable = true;
}
