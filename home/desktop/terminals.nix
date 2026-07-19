{ pkgs, ... }:
let
  zellijLauncher = pkgs.writeShellScript "zellij-launcher" ''
    exec "$SHELL" -l -c 'exec zellij --session "$(basename "$PWD")-$(date +%H%M%S)"'
  '';
in
{
  programs.alacritty = {
    enable = true;
    settings = {
      env.TERM = "xterm-256color";
      font = {
        size = 12;
        normal.family = "Maple Mono NF CN";
      };
      scrolling.multiplier = 5;
      selection.save_to_clipboard = true;
      terminal.shell.program = "${zellijLauncher}";
    };
  };

  programs.wezterm = {
    enable = true;
    extraConfig = ''
      local wezterm = require('wezterm');
      local config = wezterm.config_builder();

      config.font = wezterm.font("Maple Mono NF CN");
      config.color_scheme = "catppuccin-macchiato";
      config.hide_tab_bar_if_only_one_tab = true;
      config.window_close_confirmation = "NeverPrompt";
      config.default_prog = { "${zellijLauncher}" };

      return config
    '';
  };

  programs.kitty = {
    enable = true;
    font.name = "Maple Mono NF CN";
    font.size = 12;
    themeFile = "Catppuccin-Macchiato";
    settings = {
      term = "xterm-256color";
      shell = "${zellijLauncher}";
      shell_integration = "no-rc";
    };
  };

  programs.zellij = {
    enable = true;
    settings = {
      keybindings = "normal";
      theme = "catppuccin-macchiato";
      show_startup_tips = false;
      on_force_close = "quit";
    };
  };
}
