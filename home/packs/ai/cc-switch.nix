{ config, lib, pkgs, ... }:

let
  cfg = config.packs.ai;
in
{
  options.packs.ai.cc-switch = {
    # Opt-in extra: cc-switch — provider switcher GUI that rewrites Claude
    # Code / Codex configs directly. Migrated out of the desktop group
    # (2026-10-27), where it shipped unconditionally to every desktop host;
    # briefcase and vm, the two desktop hosts, now enable it explicitly.
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "cc-switch provider switcher, opt-in per host";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.cc-switch.enable {
      home.packages = [ pkgs."cc-switch" ];
    })
  ];
}
