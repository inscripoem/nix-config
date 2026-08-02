{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    harmonyos-sans
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
  ];

  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "HarmonyOS Sans SC" "Noto Sans CJK SC" "Noto Sans" ];
    serif = [ "Noto Serif CJK SC" "Noto Serif" ];
    monospace = [ "Maple Mono NF CN" "Noto Sans Mono CJK SC" "Noto Sans Mono" ];
  };
}
