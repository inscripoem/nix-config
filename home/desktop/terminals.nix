{ ... }:
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

  programs.wezterm = {
    enable = true;
    extraConfig = ''
      local wezterm = require('wezterm');
      local act = wezterm.action;
      local config = wezterm.config_builder();

      -- explicit symbol fallback: Maple Mono NF CN has no U+23F4-23F7 (e.g.
      -- the "⏵⏵" in Claude Code's footer) and wezterm nightly 2026-10-10's
      -- runtime fontconfig fallback misses them, firing the Font problem toast
      config.font = wezterm.font_with_fallback({ "Maple Mono NF CN", "Noto Sans Symbols 2", "Unifont" });
      config.color_scheme = "catppuccin-macchiato";
      config.window_close_confirmation = "NeverPrompt";
      config.scrollback_lines = 10000;

      -- zellij-style chrome: tab bar always on top, mode/hint bar on the bottom
      config.hide_tab_bar_if_only_one_tab = false;
      config.status_update_interval = 1000;

      -- zellij MoveFocusOrTab semantics: with a single pane in the tab,
      -- Alt+Left/Right switch tabs; otherwise they move pane focus.
      local function move_focus_or_tab(window, pane, direction)
        local tab = pane:tab();
        if tab and #tab:panes() == 1 then
          if direction == 'Left' then
            window:perform_action(act.ActivateTabRelative(-1), pane);
          else
            window:perform_action(act.ActivateTabRelative(1), pane);
          end
        else
          window:perform_action(act.ActivatePaneDirection(direction), pane);
        end
      end

      -- Chords mirror the zellij 0.45 "unlocked" mode defaults
      -- (`zellij setup --dump-config`). Ctrl+s overrides terminal flow
      -- control on purpose, exactly like zellij does. The outer pty's
      -- foreground process group stays on zellij for the whole session,
      -- so a basename match means a nested zellij owns the pane: forward
      -- the raw chord to it and act locally only outside zellij.
      local function chord(key, mods, action_or_fn)
        return {
          key = key,
          mods = mods,
          action = wezterm.action_callback(function(window, pane)
            local fg = pane:get_foreground_process_name();
            if fg and fg:match('[^/\\]+$') == 'zellij' then
              window:perform_action(act.SendKey { key = key, mods = mods }, pane);
            elseif type(action_or_fn) == 'function' then
              action_or_fn(window, pane);
            else
              window:perform_action(action_or_fn, pane);
            end
          end),
        };
      end

      config.keys = {
        chord('h', 'ALT', function(window, pane) move_focus_or_tab(window, pane, 'Left') end),
        chord('LeftArrow', 'ALT', function(window, pane) move_focus_or_tab(window, pane, 'Left') end),
        chord('l', 'ALT', function(window, pane) move_focus_or_tab(window, pane, 'Right') end),
        chord('RightArrow', 'ALT', function(window, pane) move_focus_or_tab(window, pane, 'Right') end),
        chord('j', 'ALT', act.ActivatePaneDirection 'Down'),
        chord('DownArrow', 'ALT', act.ActivatePaneDirection 'Down'),
        chord('k', 'ALT', act.ActivatePaneDirection 'Up'),
        chord('UpArrow', 'ALT', act.ActivatePaneDirection 'Up'),
        chord('n', 'ALT', act.SplitHorizontal { domain = 'CurrentPaneDomain' }),
        chord('i', 'ALT', act.MoveTabRelative(-1)),
        chord('o', 'ALT', act.MoveTabRelative(1)),

        chord('p', 'CTRL', act.ActivateKeyTable { name = 'pane_mode', one_shot = false }),
        chord('t', 'CTRL', act.ActivateKeyTable { name = 'tab_mode', one_shot = false }),
        chord('n', 'CTRL', act.ActivateKeyTable { name = 'resize_mode', one_shot = false }),
        chord('s', 'CTRL', act.ActivateKeyTable { name = 'scroll_mode', one_shot = false }),
      };

      -- Modes ported from zellij defaults: action keys pop back to normal
      -- mode, navigation keys stay inside the mode, Escape re-enters normal.
      config.key_tables = {
        pane_mode = {
          { key = 'n', action = act.Multiple { act.SplitHorizontal { domain = 'CurrentPaneDomain' }, act.PopKeyTable } },
          { key = 'd', action = act.Multiple { act.SplitVertical { domain = 'CurrentPaneDomain' }, act.PopKeyTable } },
          { key = 'r', action = act.Multiple { act.SplitHorizontal { domain = 'CurrentPaneDomain' }, act.PopKeyTable } },
          { key = 'x', action = act.Multiple { act.CloseCurrentPane { confirm = false }, act.PopKeyTable } },
          { key = 'f', action = act.Multiple { act.TogglePaneZoomState, act.PopKeyTable } },
          { key = 'h', action = act.ActivatePaneDirection 'Left' },
          { key = 'LeftArrow', action = act.ActivatePaneDirection 'Left' },
          { key = 'l', action = act.ActivatePaneDirection 'Right' },
          { key = 'RightArrow', action = act.ActivatePaneDirection 'Right' },
          { key = 'j', action = act.ActivatePaneDirection 'Down' },
          { key = 'DownArrow', action = act.ActivatePaneDirection 'Down' },
          { key = 'k', action = act.ActivatePaneDirection 'Up' },
          { key = 'UpArrow', action = act.ActivatePaneDirection 'Up' },
          { key = 'Escape', action = act.PopKeyTable },
          { key = 'p', mods = 'CTRL', action = act.PopKeyTable },
        },
        tab_mode = {
          { key = 'n', action = act.Multiple { act.SpawnTab 'CurrentPaneDomain', act.PopKeyTable } },
          { key = 'x', action = act.Multiple { act.CloseCurrentTab { confirm = false }, act.PopKeyTable } },
          { key = 'r', action = act.Multiple {
              act.PromptInputLine {
                description = 'Enter tab name',
                action = wezterm.action_callback(function(window, pane, line)
                  if line and #line > 0 then window:active_tab():set_title(line) end
                end),
              },
              act.PopKeyTable,
            } },
          { key = 'h', action = act.ActivateTabRelative(-1) },
          { key = 'LeftArrow', action = act.ActivateTabRelative(-1) },
          { key = 'l', action = act.ActivateTabRelative(1) },
          { key = 'RightArrow', action = act.ActivateTabRelative(1) },
          { key = 'Escape', action = act.PopKeyTable },
          { key = 't', mods = 'CTRL', action = act.PopKeyTable },
        },
        resize_mode = {
          -- wezterm unstable-2026-08-31 rejects negative AdjustPaneSize
          -- amounts at config validation, so only grow is bound here;
          -- shrink keys can return when the build accepts them.
          { key = 'h', action = act.AdjustPaneSize { 'Left', 1 } },
          { key = 'LeftArrow', action = act.AdjustPaneSize { 'Left', 1 } },
          { key = 'l', action = act.AdjustPaneSize { 'Right', 1 } },
          { key = 'RightArrow', action = act.AdjustPaneSize { 'Right', 1 } },
          { key = 'j', action = act.AdjustPaneSize { 'Down', 1 } },
          { key = 'DownArrow', action = act.AdjustPaneSize { 'Down', 1 } },
          { key = 'k', action = act.AdjustPaneSize { 'Up', 1 } },
          { key = 'UpArrow', action = act.AdjustPaneSize { 'Up', 1 } },
          { key = 'Escape', action = act.PopKeyTable },
          { key = 'n', mods = 'CTRL', action = act.PopKeyTable },
        },
        scroll_mode = {
          { key = 'j', action = act.ScrollByLine(1) },
          { key = 'DownArrow', action = act.ScrollByLine(1) },
          { key = 'k', action = act.ScrollByLine(-1) },
          { key = 'UpArrow', action = act.ScrollByLine(-1) },
          { key = 'd', action = act.ScrollByPage(0.5) },
          { key = 'u', action = act.ScrollByPage(-0.5) },
          { key = 'PageDown', action = act.ScrollByPage(1) },
          { key = 'PageUp', action = act.ScrollByPage(-1) },
          { key = 'Escape', action = act.PopKeyTable },
          { key = 's', mods = 'CTRL', action = act.PopKeyTable },
        },
      };

      -- zellij-style bottom bar: mode label and per-mode key hints on the
      -- left, current working directory on the right.
      local mode_hints = {
        pane_mode = ' [n]new [d]down [r]right [x]close [f]zoom [hjkl]nav ESC=exit',
        tab_mode = ' [n]new [x]close [r]rename [hl]prev/next ESC=exit',
        resize_mode = ' [hjkl]grow ESC=exit',
        scroll_mode = ' [jk]line [ud]half-page ESC=exit',
      };

      wezterm.on('update-right-status', function(window, pane)
        local mode = window:active_key_table();
        local cells = {};
        if mode then
          table.insert(cells, { Foreground = { Color = '#c6a0f6' } });
          table.insert(cells, { Attribute = { Intensity = 'Bold' } });
          table.insert(cells, { Text = ' ' .. mode .. ' ' });
          table.insert(cells, { Foreground = { Color = '#9399b2' } });
          table.insert(cells, { Attribute = { Intensity = 'Normal' } });
          table.insert(cells, { Text = mode_hints[mode] or "" });
        else
          table.insert(cells, { Foreground = { Color = '#6e738d' } });
          table.insert(cells, { Text = ' normal ' });
        end
        window:set_left_status(wezterm.format(cells));
        local cwd_uri = pane.current_working_dir;
        local cwd = cwd_uri and cwd_uri.file_path or nil;
        window:set_right_status(cwd and (' ' .. cwd .. ' ') or "");
      end);

      return config
    '';
  };

  programs.zellij = {
    enable = true;
    settings = {
      keybindings = "normal";
      theme = "catppuccin-macchiato";
      show_startup_tips = false;
      on_force_close = "quit";
      # Manual screen-like slot: bare `zellij` re-enters the single named
      # session (attach-or-create) instead of spawning randomly-named ones.
      session_name = "main";
      attach_to_session = true;
    };
  };

  programs.kitty = {
    enable = true;
    font.name = "Maple Mono NF CN";
    font.size = 12;
    themeFile = "Catppuccin-Macchiato";
    settings.term = "xterm-256color";
  };
}
