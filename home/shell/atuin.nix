{
  programs.atuin = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    settings = {
      auto_sync = false;
      update_check = false;
      style = "compact";
      inline_height = 20;
      show_preview = true;
      filter_mode = "global";
      filter_mode_shell_up_key_binding = "global";
      search_mode = "fuzzy";
    };
  };
}
