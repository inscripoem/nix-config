{ config, lib, pkgs, llm-agents, ... }:

let
  cfg = config.packs.ai;
  agentPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  options.packs.ai.codex = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "codex CLI";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.codex.enable {
      home.packages = [ agentPkgs.codex ];
    })
  ];
}
