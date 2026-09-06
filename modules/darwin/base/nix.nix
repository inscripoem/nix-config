{ ... }:

{
  # Phase 1 keeps the existing Lix installer, daemon, and nix.conf intact.
  # Revisit only after the first Darwin generation has proven reversible.
  nix.enable = false;
}
