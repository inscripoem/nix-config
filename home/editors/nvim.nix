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
}
