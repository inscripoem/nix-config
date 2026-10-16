{
  imports = [ ../desktop.nix ];

  packs.ai.enable = true;
  # Opt-in extra from packs.ai (defaults to false) — this host only.
  packs.ai.hermes-agent.enable = true;
  packs.ai.workbuddy.enable = true;
  packs.ai.orca.enable = true;
  packs.creative.enable = true;
  # Opt-in extra from packs.creative (defaults to false) — this host only.
  packs.creative.photocraft.enable = true;
  packs.gaming.enable = true;
  packs.office.enable = true;
  packs.onedrive.enable = true;
  packs.toolchain.enable = true;

  desktop.emacs.enable = true;
}
