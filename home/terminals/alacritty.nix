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
    };
  };
}
