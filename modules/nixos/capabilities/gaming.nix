{ config, lib, pkgs, vars, ... }:
let cfg = config.modules.capabilities.gaming;
in {
  options.modules.capabilities.gaming.enable =
    lib.mkEnableOption "gaming suite (Steam, Proton-GE, gamemode)";
  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      # https://github.com/GloriousEggroll/proton-ge-custom
      extraCompatPackages = [
        pkgs.proton-ge-bin
        pkgs.dwproton-bin  # Arknights: Endfield (ACE anti-cheat patches)
      ];
    };
    programs.gamemode.enable = true;

    # AAGL launchers (Genshin/HSR/ZZZ, with CN server support)
    # https://github.com/ezKEa/aagl-gtk-on-nix
    programs.anime-game-launcher.enable = true;        # Genshin Impact
    programs.honkers-railway-launcher.enable = true;   # Honkai: Star Rail
    # programs.sleepy-launcher.enable = true;          # Zenless Zone Zero (optional)

    # Waydroid Android container (for Arknights + MAA automation)
    # https://wiki.nixos.org/wiki/Waydroid
    virtualisation.waydroid.enable = true;
    # kernel ≥ 6.17 dropped ip_tables, use nftables variant
    virtualisation.waydroid.package = pkgs.waydroid-nftables;

    # WuWa CLI manager (download/update/switch servers)
    # MAA for Arknights automation (auto-farming, base management)
    # Waydroid-helper for ARM translation in Android container
    environment.systemPackages = [
      pkgs.ww-manager
      pkgs.maa-assistant-arknights
      pkgs.maa-cli
      pkgs.waydroid-helper
      pkgs.android-tools
    ];
  };
}
