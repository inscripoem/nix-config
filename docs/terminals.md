# Terminal stack roles and the wezterm key layer

Four terminals share `home/desktop/terminals.nix`, each with a role chosen by
constraint rather than preference. Read this before editing that file or
touching the session strategy; the validation workflow at the end is not
optional.

## 1. Role model

| Terminal | Role | Why it holds the seat |
|---|---|---|
| WezTerm | Daily driver | The only candidate that can host the interaction layer below. Also the only one beside Kitty that implements the kitty graphics protocol, so Yazi image previews work. |
| Zellij | Manual screen-like slot | Kept installed but out of the default spawn path. Bare `zellij` attaches to (or creates) the single session `main` (`session_name` + `attach_to_session`), detach with `Ctrl+o d`. `zellij ls` therefore only ever shows `main`. |
| Alacritty | Scratch terminal | Fastest cold start and lowest footprint of the installed set; deliberately bare shell. Niri's own default binding is Alacritty for the same reason. |
| Kitty | Graphics reference and toolbox | Reference implementation of the kitty graphics protocol (arbitrates "implementation bug vs my config" when image rendering misbehaves) and host of kittens with no WezTerm equivalent: `transfer`, `ssh` (login-shell environment and locale setup on the remote), `diff`, `broadcast`. Most kittens require Kitty as the host terminal, so the toolbox is inaccessible from WezTerm. |

Constraints that drove the split:

- Alacritty supports neither the kitty graphics protocol nor sixel and has no
  text shaping (no ligatures), so it cannot be the daily driver.
- Kitty's configuration model is a flat `map` table with no modal keybindings,
  no programmable status bar, and no event callbacks. The zellij-style layer
  below is structurally inexpressible in it.
- WezTerm's cross-platform config would carry the same key layer to macOS or
  Windows hosts if this repo ever declares terminals there.

## 2. The zellij layer inside WezTerm

The layer ports zellij 0.45 defaults, transcribed from
`zellij setup --dump-config` on the installed binary, not from memory:

- Direct chords mirror zellij's unlocked mode: `Alt+hjkl`/arrows move pane
  focus, `Alt+n` splits, `Alt+i`/`Alt+o` reorder tabs, `Alt+Left/Right` use an
  `action_callback` that switches tabs when the tab holds a single pane and
  moves pane focus otherwise (zellij's `MoveFocusOrTab` semantics).
- `Ctrl+p`/`Ctrl+t`/`Ctrl+n`/`Ctrl+s` activate `key_tables` named
  `pane_mode`/`tab_mode`/`resize_mode`/`scroll_mode` with `one_shot = false`.
  Action keys combine with `PopKeyTable` via `act.Multiple` so the mode exits
  after acting, navigation keys stay inside the mode, and `Escape` re-enters
  normal mode.
- `update-right-status` draws a zellij-style bottom bar: mode label and
  per-mode key hints on the left, working directory on the right. The tab bar
  stays visible (`hide_tab_bar_if_only_one_tab = false`).

`Ctrl+s` deliberately shadows terminal flow control, exactly as zellij does.
`Ctrl+Shift+` variants of WezTerm defaults remain untouched.

## 3. Session strategy

The previous scheme spawned a timestamped zellij session per terminal window.
It guaranteed per-window canvases (no size negotiation between windows) but
leaked one EXITED session per closed window — roughly 80 accumulated entries
that made `zellij ls` unusable and made attach unusable in practice.

The replacement accepts that windows are the unit of persistence: closing a
window discards its processes, and long-lived windows serve as the "keep it
running" mechanism on a desktop that never powers off. Anything that must
survive a window close runs in the manual `main` slot via bare `zellij`. Do
not reintroduce spawn-per-window launchers and do not add auto-start of
zellij in shells; it recreates the leak.

## 4. Known limitations

- `resize_mode` can only grow panes. WezTerm
  `0-unstable-2026-08-31` rejects negative `AdjustPaneSize` amounts at config
  validation; the shrink bindings are omitted until a build accepts them.
- WezTerm has no floating panes, so zellij's `Alt+f` has no port. Pane usage
  is rare enough that this was accepted.
- No leader key: the layer uses direct chords, so readline `Ctrl+A`
  (beginning-of-line) reaches the shell unmodified.

## 5. Validation workflow for changes

`nix eval` passing does not mean the Lua runs, and the Lua loading does not
mean the config was accepted. All three layers must pass, in this order:

1. `nix eval --no-warn-dirty .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`
   for `briefcase` and `vm` (the `desktop` class hosts).
2. Extract the exact artifact Home Manager will render, then headless-check
   it:
   ```
   nix eval --raw --no-warn-dirty \
     .#nixosConfigurations.briefcase.config.home-manager.users.inscripoem.programs.wezterm.extraConfig \
     > /tmp/wez.lua
   wezterm --config-file /tmp/wez.lua show-keys
   ```
3. Check the bindings actually registered. `show-keys` renders
   `action_callback` entries as `EmitEvent("user-defined-N")` and does not
   list named key tables; use `show-keys --lua` for those.

Failure modes learned the hard way:

- **Invalid actions fail silently.** One malformed action makes WezTerm fall
  back to built-in defaults: `show-keys` exits 0 with empty stderr and prints
  only the default table. Detect this by adding a canary binding (for example
  `F12 → ShowDebugOverlay`) and grepping the output for it.
- **`config_builder()` does not prepopulate `config.keys`** (it is `nil`);
  `table.insert` on it crashes. Assign `config.keys = { ... }` directly —
  assignment extends the defaults rather than replacing them.
- **Lua empty strings terminate the Nix string.** Inside `extraConfig = ''
  ... '';` a literal `''` ends the string; write Lua empty strings as `""`.
- `show-keys` on an extraction script's regex output proves nothing about
  the Nix layer — the regex happily extracts a complete Lua from a
  syntactically broken Nix file. Extract via `nix eval` (step 2), not sed.
