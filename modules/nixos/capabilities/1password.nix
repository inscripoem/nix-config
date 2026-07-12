{ config, lib, pkgs, ... }:
let cfg = config.modules.capabilities."1password";
in {
  options.modules.capabilities."1password".enable =
    lib.mkEnableOption "1Password system integration";
  config = lib.mkIf cfg.enable {
    # P2: programs._1password, programs._1password-gui, browser allowlist
  };
}
