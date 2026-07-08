{ pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    plugins = with pkgs.vimPlugins; [
      flash-nvim
    ];

    extraLuaConfig = ''
      require("flash").setup({
        -- search labels
        labels = "asdfghjklqwertyuiopzxcvbnm",
        search = {
          multi_window = true,
          mode = "exact",
        },
        jump = {
          jumplist = true,
          pos = "start",
        },
        label = {
          uppercase = true,
          style = "overlay",
          reuse = "lowercase",
        },
        highlight = {
          backdrop = true,
        },
        modes = {
          char = {
            enabled = true,
            jump_labels = true,
          },
          treesitter = {
            labels = "abcdefghijklmnopqrstuvwxyz",
          },
        },
      })

      -- Keymaps
      vim.keymap.set({ "n", "x", "o" }, "s", function() require("flash").jump() end, { desc = "Flash" })
      vim.keymap.set({ "n", "x", "o" }, "S", function() require("flash").treesitter() end, { desc = "Flash Treesitter" })
      vim.keymap.set("o", "r", function() require("flash").remote() end, { desc = "Remote Flash" })
    '';
  };

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
