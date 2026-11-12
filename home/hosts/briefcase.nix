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
  # Opt-in member of packs/remote.nix (defaults to false) — this host only.
  packs.remote.netcatty.enable = true;
  packs.toolchain.enable = true;

  desktop.emacs.enable = true;

  # Pin the compositor's primary GPU to the WX 5100 for the hermes-kms
  # virtual-display experiment. Smithay's primary_gpu rule (first card with
  # a render node; no boot_vga tiebreaker on this platform) picks the
  # hermes-kms virtual card (card0) over the real GPU (card1) whenever the
  # module is loaded, and no GL renderer can initialize on the virtual card
  # — display-only fallbacks then have nowhere to fall back to and virtual
  # display sessions fail with an empty format set. The by-path address is
  # slot-stable. See docs/remote-desktop.md, hermes-kms section.
  programs.niri.settings.debug."render-drm-device" =
    "/dev/dri/by-path/pci-0000:01:00.0-render";
}
