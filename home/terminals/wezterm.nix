{
  programs.wezterm = {
    enable = true;
    extraConfig = ''
      local wezterm = require('wezterm');
      local config = wezterm.config_builder();

      config.font = wezterm.font("Maple Mono NF CN");
      config.color_scheme = "catppuccin-macchiato";
      config.hide_tab_bar_if_only_one_tab = true;
      config.default_prog = { os.getenv("SHELL"), "-l", "-c", "zellij attach --index 0 --create"};

      return config
    '';
  };
}
