{ imports = [
  ../desktop.nix
  ../packs/creative.nix
  ../packs/toolchain.nix
  ../packs/ai.nix
  ../packs/gaming.nix
];
  packs.ai.enable = true;
}
