{ pkgs, ... }:

{
  programs.niri = {
    # 使用 nixpkgs 中的 niri，可以命中 NixOS 官方 cache
    package = pkgs.niri;

    settings = {
      binds = {
        "Ctrl+Alt+T".action.spawn = "wezterm";
        "Alt+Space".action.spawn = [ "dms" "ipc" "call" "spotlight" "toggle" ];
        "Mod+Q".action.close-window = [];
        "Mod+Shift+F".action.maximize-column = [];

        "Mod+Left".action.focus-column-left = [];
        "Mod+Right".action.focus-column-right = [];
        "Mod+Up".action.focus-window-up = [];
        "Mod+Down".action.focus-window-down = [];

        "Mod+Shift+Left".action.move-column-left = [];
        "Mod+Shift+Right".action.move-column-right = [];
        "Mod+Shift+Up".action.move-window-up = [];
        "Mod+Shift+Down".action.move-window-down = [];

        "Mod+1".action.focus-workspace = 1;
        "Mod+2".action.focus-workspace = 2;
        "Mod+3".action.focus-workspace = 3;
        "Mod+4".action.focus-workspace = 4;
        "Mod+5".action.focus-workspace = 5;

        "Mod+Shift+1".action.move-window-to-workspace = 1;
        "Mod+Shift+2".action.move-window-to-workspace = 2;
        "Mod+Shift+3".action.move-window-to-workspace = 3;
        "Mod+Shift+4".action.move-window-to-workspace = 4;
        "Mod+Shift+5".action.move-window-to-workspace = 5;

        "Print".action.screenshot = [];
        "Ctrl+Print".action.screenshot-screen = [];

        "Mod+Shift+E".action.quit = [];

        "XF86AudioRaiseVolume".action.spawn = [ "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1+" ];
        "XF86AudioLowerVolume".action.spawn = [ "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1-" ];
        "XF86AudioMute".action.spawn = [ "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle" ];

        "XF86MonBrightnessUp".action.spawn = [ "brightnessctl" "set" "5%+" ];
        "XF86MonBrightnessDown".action.spawn = [ "brightnessctl" "set" "5%-" ];
      };

      spawn-at-startup = [
        { command = [ "dms" "run" ]; }
      ];

      environment = {
        "NIXOS_OZONE_WL" = "1";
        "XDG_CURRENT_DESKTOP" = "niri";
        "XDG_SESSION_TYPE" = "wayland";
        "XDG_SESSION_DESKTOP" = "niri";
        # Force DMS to use an icon theme with light panel icons on the dark bar.
        "QS_ICON_THEME" = "breeze-dark";
      };
    };
  };
}
