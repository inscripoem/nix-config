{ pkgs, llm-agents, ... }:
{
  imports = [
    ./aichat.nix
    ./cc-switch.nix
    ./opencode.nix
  ];

  home.packages = [
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.ck
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.rtk
  ];
}
