{ config, lib, pkgs, ... }:
let
  cfg = config.packs.office;
in {
  options.packs.office.enable = lib.mkEnableOption "office/collaboration tooling (lark-cli and friends)";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.lark-cli ];
  };
}
