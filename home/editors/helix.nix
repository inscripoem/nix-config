{
  programs.helix = {
    enable = true;
    settings = {
      theme = "catppuccin_macchiato";
      editor = {
        line-number = "relative";
        cursorline = true;
        color-modes = true;
        bufferline = "multiple";
        true-color = true;
        completion-replace = true;
        cursor-shape = {
          insert = "bar";
          normal = "block";
          select = "underline";
        };
        file-picker.hidden = false;
        indent-guides = {
          render = true;
          character = "│";
        };
        lsp = {
          display-messages = true;
          display-inlay-hints = true;
        };
        statusline.center = [ "position" "file-encoding" ];
      };
    };
  };
}
