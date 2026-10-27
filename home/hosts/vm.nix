{
  imports = [ ../desktop.nix ];

  # cc-switch moved into packs.ai as an opt-in extra (was unconditional in
  # the desktop group); this line keeps it installed here. Member options
  # are gated individually, so this does not pull in the ai pack bundle.
  packs.ai.cc-switch.enable = true;
}
