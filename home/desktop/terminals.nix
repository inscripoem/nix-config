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
      terminal = {
        shell = {
          program = "/etc/profiles/per-user/inscripoem/bin/zsh";
          args = [ "-l" "-c" "exec zellij --session \"$(basename \"$PWD\")-$(date +%H%M%S)\"" ];
        };
      };
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
      config.default_prog = { os.getenv("SHELL"), "-l", "-c", "exec zellij --session \"$(basename \"$PWD\")-$(date +%H%M%S)\""};

      return config
    '';
  };

  programs.zellij = {
    enable = true;
    settings = {
      keybindings = "normal";
      theme = "catppuccin-macchiato";
      show_startup_tips = false;
    };
  };
}
