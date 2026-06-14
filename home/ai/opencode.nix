{ pkgs, llm-agents, ... }:

{
  home.packages = [
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode
  ];

  # Required by oh-my-opencode-slim's Orchestrator to dispatch specialists
  # as background tasks. opencode reads it at startup; its own installer
  # tries to patch ~/.zshrc, which is a read-only nix-store symlink on
  # NixOS, so we declare it here so every shell and any GUI launcher
  # (KDE menu, krunner, IDE) sees the same value.
  home.sessionVariables.OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS = "true";
}
