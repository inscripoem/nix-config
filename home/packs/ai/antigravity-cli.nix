{ config, lib, pkgs, llm-agents, ... }:

let
  cfg = config.packs.ai;
  agentPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  options.packs.ai.antigravity-cli = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "antigravity-cli";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.antigravity-cli.enable {
      home.packages = [ agentPkgs.antigravity-cli ];
    })
  ];
}
