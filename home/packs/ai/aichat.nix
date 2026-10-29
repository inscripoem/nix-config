{ config, lib, ... }:

let
  cfg = config.packs.ai;
in
{
  options.packs.ai.aichat = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "aichat — TUI chat client";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.aichat.enable {
      programs.aichat.enable = true;
    })
  ];
}
