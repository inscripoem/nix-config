{ config, lib, pkgs, llm-agents, ... }:

let
  cfg = config.packs.ai;
  agentPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  options.packs.ai.rtk = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "rtk CLI";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.rtk.enable {
      home.packages = [ agentPkgs.rtk ];
    })
  ];
}
