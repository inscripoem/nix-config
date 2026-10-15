{ pkgs, ... }:
{
  # ArtCraft apps' text tools look for fonts only in /usr/share/fonts and
  # do not use fontconfig; expose the system font dir there.
  fonts.fontDir.enable = true;
  systemd.tmpfiles.rules = [
    "d /usr/share 0755 root root -"
    "L+ /usr/share/fonts - - - - /run/current-system/sw/share/X11/fonts"
  ];

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
