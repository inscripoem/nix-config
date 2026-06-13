# Atuin × zsh-autosuggestions on `briefcase`

A bug log for the Atuin / zsh-autosuggestions integration on this machine.
The **configuration** lives in `home/shell/zsh.nix` (autosuggestions,
strategy, `initContent`) and `home/shell/integrations.nix` (Atuin itself);
this file explains **why** each knob is set the way it is, so a future
"clean up" doesn't quietly re-introduce a known failure mode.

Stack:

- zsh 5.9
- home-manager `programs.zsh` with `autosuggestion.enable = true`,
  ships `zsh-autosuggestions` **0.7.1**
- `programs.atuin.enable = true` (currently 18.x), zsh integration via
  `eval "$(atuin init zsh)"` injected by home-manager
- No oh-my-zsh, no sheldon — home-manager sources everything directly into
  `~/.zshrc`

What we want, simultaneously:

1. **Up arrow** opens Atuin's full-screen TUI (session-scoped search).
2. **Ctrl-R** opens Atuin's TUI (global search).
3. **Ghost text** (the inline grey suggestion) keeps working, and prefers
   Atuin's smart matcher over plain history.

If we just turn both modules on and walk away, only #2 works.

---

## 1. The two pieces and how they hook into ZLE

### Atuin (`atuin init zsh`)

`atuin init zsh` does roughly three things:

- Defines widgets: `atuin-search`, `atuin-search-viins`, `atuin-search-vicmd`,
  `atuin-up-search`, `atuin-up-search-viins`, `atuin-up-search-vicmd`.
  Each one runs `atuin search` in a TUI and pastes the chosen command back
  into the buffer.
- Registers them with `zle -N`.
- Binds keys:
  - `^R` → `atuin-search`
  - `^[[A` / `^P` / vi-mode `k` → `atuin-up-search`
- Defines `_zsh_autosuggest_strategy_atuin`, an autosuggestions
  *strategy provider* that asks `atuin search --cmd-only --limit 1` for a
  ghost text candidate.

So Atuin is two integrations bolted together: ZLE keybindings (Up / Ctrl-R)
**and** an autosuggestions strategy function.

### zsh-autosuggestions 0.7.1

On `source`, it:

- Reads `ZSH_AUTOSUGGEST_STRATEGY` (default: `(history)`), and for each
  entry `<name>` looks up `_zsh_autosuggest_strategy_<name>`.
  **If a strategy function is missing at source time, it prints a hard
  error and disables that strategy permanently for the session.**
- Wraps every ZLE widget into a `<widget>-autosuggest-strategy` shim. Each
  shim decides, by widget *name*, whether to:
  - **accept** the suggestion and keep it (e.g. `forward-char`),
  - **clear** the suggestion (default for "unknown" widgets),
  - **execute** the suggestion (e.g. `accept-line`),
  - **partial-accept**, etc.

  The widget-name → action mapping is controlled by:
  - `ZSH_AUTOSUGGEST_ACCEPT_WIDGETS`
  - `ZSH_AUTOSUGGEST_CLEAR_WIDGETS`     ← the dangerous one
  - `ZSH_AUTOSUGGEST_EXECUTE_WIDGETS`
  - `ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS`
  - `ZSH_AUTOSUGGEST_IGNORE_WIDGETS`    ← the nuclear "do not touch" list

That widget-wrapping is where the conflict comes from.

---

## 2. The conflicts, in execution order

### 2.1 Source-order conflict: `_zsh_autosuggest_strategy_atuin` not defined yet

home-manager's generated `~/.zshrc` ends up roughly like:

```
source zsh-autosuggestions.zsh    # ← line ~11
...
eval "$(atuin init zsh)"          # ← line ~71, injected by programs.atuin
```

If we set `ZSH_AUTOSUGGEST_STRATEGY=(atuin history completion)` *before*
autosuggestions is sourced, the strategy validation fires immediately and
fails: at that moment Atuin hasn't run yet, so
`_zsh_autosuggest_strategy_atuin` doesn't exist. Autosuggestions then
drops `atuin` from its strategy chain and never re-checks. Ghost text falls
back to plain `history`, silently.

**Fix:** declare a no-op `_zsh_autosuggest_strategy_atuin() { :; }` at the
very top of `.zshrc` (via `lib.mkBefore` in `initContent`). It satisfies
the source-time check; `atuin init zsh` later redefines the function with
the real implementation, and the new definition is what actually gets
called when autosuggestions fetches a suggestion.

### 2.2 Type-system conflict: home-manager's `strategy` option rejects `"atuin"`

The natural fix to 2.1 would be:

```nix
programs.zsh.autosuggestion.strategy = [ "atuin" "history" "completion" ];
```

home-manager refuses with:

```
A definition for option ... is not of type
'one of "history", "completion", "match_prev_cmd"'
```

The enum check is hardcoded into the module — it has no way to know about
third-party strategies. Reasonable, just inconvenient.

**Fix:** set `autosuggestion.strategy = [ ];` so home-manager generates
no `ZSH_AUTOSUGGEST_STRATEGY=...` line at all, then write the line
ourselves via `initContent` (after the `atuin init zsh` block).
`autosuggestion.enable = true` is still required to actually source the
plugin.

### 2.3 Widget-policy conflict: Up arrow gets eaten

This is the symptom that gave the bug its name: **Ctrl-R opens Atuin
fine, Up arrow doesn't.** Both keys are bound to Atuin widgets by
`atuin init zsh`, so it isn't a keybinding problem.

It's the autosuggestions widget wrapper. After autosuggestions is sourced,
every widget is wrapped. When you press Up, ZLE actually invokes
`atuin-up-search-autosuggest-strategy` (the wrapper), not `atuin-up-search`
itself. The wrapper looks up `atuin-up-search` in its widget-name buckets:

- Not in `ACCEPT_WIDGETS` → don't keep the suggestion.
- Not in `EXECUTE_WIDGETS` → don't run the buffer.
- Not in `IGNORE_WIDGETS` → don't bypass.
- Falls through to the default: **clear the suggestion, then invoke the
  underlying widget after stripping the postdisplay region.**

The "strip postdisplay" step touches ZLE state in a way that breaks
Atuin's full-screen TUI takeover on Up arrow on 0.7.1 (Ctrl-R, going
through a slightly different code path in Atuin, survives it). Net effect:
Up appears to do nothing, or just moves through history line by line.

Why does this never happen on a "normal" install (sheldon + atuin on a
non-NixOS box)? Two reasons:

- sheldon usually sources `atuin init zsh` **before** zsh-autosuggestions,
  so by the time autosuggestions builds its widget table, the atuin
  widgets already exist and get wrapped in a friendlier order. home-manager
  hardcodes autosuggestions to be sourced near the top of `.zshrc`,
  inverting that order.
- Some distros' Atuin packaging ships an `atuin init zsh` that *itself*
  appends its widgets to `ZSH_AUTOSUGGEST_*_WIDGETS`. Upstream removed
  that in newer releases, leaving the responsibility to the user.

**Fix:** append the six Atuin widgets to `ZSH_AUTOSUGGEST_ACCEPT_WIDGETS`
after `atuin init zsh` has run. `ACCEPT` is the right bucket — semantically
you *are* accepting whatever's in the buffer and then handing control to a
new full-screen widget. The guard
`if typeset -p ZSH_AUTOSUGGEST_ACCEPT_WIDGETS >/dev/null 2>&1` exists so a
future version of autosuggestions that drops the variable (or a config
where autosuggestion is disabled) doesn't error out here.

If a future autosuggestions version still swallows Up after this, the
escalation path is `ZSH_AUTOSUGGEST_IGNORE_WIDGETS+=(atuin-*)`, which
bypasses the wrapper entirely. We haven't needed it on 0.7.1.

---

## 3. The final layout in `home/shell/zsh.nix`

In execution order, the generated `~/.zshrc` becomes:

| Line   | Content                                            | Why                                              |
|--------|----------------------------------------------------|--------------------------------------------------|
| top    | `_zsh_autosuggest_strategy_atuin() { :; }`         | satisfies 2.1, stub gets overridden later        |
| ~11    | `source zsh-autosuggestions.zsh`                   | home-manager, can't move                         |
| ~71    | `eval "$(atuin init zsh)"`                         | home-manager, real strategy function lands here  |
| bottom | `ZSH_AUTOSUGGEST_STRATEGY=(atuin history completion)` | fixes 2.2 (can't set it earlier without enum)  |
| bottom | `ZSH_AUTOSUGGEST_ACCEPT_WIDGETS+=(atuin-* ...)`    | fixes 2.3                                        |

In Nix this is expressed as a `lib.mkMerge` of one `lib.mkBefore` (top)
and one `lib.mkAfter` (bottom) snippet.

---

## 4. Verifying without rebuilding

```sh
# Build just the .zshrc derivation:
nix build --no-link --print-out-paths \
  .#nixosConfigurations.briefcase.config.home-manager.users.inscripoem.home.file.\"./.zshrc\".source

# Then:
grep -nE 'atuin|AUTOSUGGEST|autosuggestions|_zsh_autosuggest' <out>
```

Expected: stub on line 1, autosuggestions source before `atuin init`, and
the two `mkAfter` snippets at the bottom.

After `nhs`, **open a new terminal** — the running zsh has already wrapped
the widgets, so the policy changes only take effect in a fresh shell.

Quick smoke test in the new shell:

```sh
print -l "${ZSH_AUTOSUGGEST_STRATEGY[@]}"        # atuin history completion
print -l "${ZSH_AUTOSUGGEST_ACCEPT_WIDGETS[@]}" | grep atuin   # 6 widgets
bindkey '^[[A'                                   # → atuin-up-search
```

---

## 5. Things that look like "cleanups" but will re-break this

- "Just remove the `_zsh_autosuggest_strategy_atuin() { :; }` stub, atuin
  defines it anyway" → re-introduces 2.1, silently downgrades ghost text
  to history-only.
- "Set `programs.zsh.autosuggestion.strategy = [ \"history\" ];` for type
  safety" → overrides the `mkAfter` line, same downgrade.
- "Move atuin out of `programs.atuin.enableZshIntegration` and source it
  manually somewhere higher" → can fix 2.3 by accident but breaks
  home-manager's session-variable plumbing for Atuin (`ATUIN_SESSION`,
  history filtering). Don't.
- "Drop the `ACCEPT_WIDGETS` block, Ctrl-R works fine" → Up arrow regresses.
  Both keys must be in the whitelist, even though only Up is observably
  affected on 0.7.1, because future autosuggestions releases may tighten
  the Ctrl-R path too.
