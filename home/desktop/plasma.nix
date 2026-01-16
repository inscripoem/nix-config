{ pkgs, ... }:

{
  nixGL.vulkan.enable = true;

  programs.plasma = {
    enable = true;
    hotkeys.commands."launch-wezterm" = {
      name = "Launch Wezterm";
      key = "Ctrl+Alt+T";
      command = "wezterm";
    };
    configFile."kwinrc"."Wayland"."VirtualKeyboard" = "org.fcitx.Fcitx5";
  };
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-wlr
    ];
    config = {
      common = {
        default = [
          "gtk"
        ];
      };
    };
  };
}
