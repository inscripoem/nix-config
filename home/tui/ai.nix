{ pkgs, llm-agents, ... }:

{
  programs.aichat = {
    enable = true;
    # settings = {
    #   # Configure LLM providers here
    #   # model = "openai:gpt-4";
    #   # clients = [
    #   #   {
    #   #     type = "openai";
    #   #     api_key = "env:OPENAI_API_KEY";
    #   #   }
    #   # ];
    # };
  };

  home.packages = [
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.ck
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.rtk
  ];

  # Required by oh-my-opencode-slim's Orchestrator to dispatch specialists
  # as background tasks. opencode reads it at startup; its own installer
  # tries to patch ~/.zshrc, which is a read-only nix-store symlink on
  # NixOS, so we declare it here so every shell and any GUI launcher
  # (KDE menu, krunner, IDE) sees the same value.
  home.sessionVariables.OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS = "true";
}
