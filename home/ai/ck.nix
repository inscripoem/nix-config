{ pkgs, llm-agents, ... }:

{
  home.packages = [
    # Local-first semantic + BM25 hybrid code search for agents and humans.
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.ck
  ];
}
