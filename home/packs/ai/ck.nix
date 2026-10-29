{ config, lib, pkgs, llm-agents, ... }:

let
  cfg = config.packs.ai;
  agentPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  options.packs.ai.ck = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "ck agent CLI";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.ck.enable {
      home.packages = [ agentPkgs.ck ];
    })
  ];
}
