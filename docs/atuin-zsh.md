# Atuin and Zsh autosuggestions

[home/core/shell.nix](../home/core/shell.nix) integrates Atuin with
zsh-autosuggestions. Up opens directory-scoped history, Ctrl-R opens global
history, and inline suggestions prefer Atuin with history/completion fallbacks.

## Initialization order

The configuration retains the following ordering and widget policy from the
Zsh 5.9 / zsh-autosuggestions 0.7.1 integration:

| Order | Configuration | Reason |
|---|---|---|
| Before autosuggestions | Empty `_zsh_autosuggest_strategy_atuin` function | Makes the strategy name available before Atuin initialization |
| HM program integration | `atuin init zsh` | Defines the real strategy and search widgets |
| After Atuin | `ZSH_AUTOSUGGEST_STRATEGY=(atuin history completion)` | Selects the custom strategy outside HM's restricted option type |
| After Atuin | Six widgets in `ZSH_AUTOSUGGEST_ACCEPT_WIDGETS` | Preserves the working Up/Ctrl-R behavior with widget wrapping |

`programs.zsh.autosuggestion.strategy` is intentionally empty: the pinned HM
option accepts only `history`, `completion`, and `match_prev_cmd`. The empty
list suppresses HM's assignment, so `initContent` can select the custom Atuin
strategy after Atuin defines it. A nonempty list would add an earlier assignment;
the later `mkAfter` assignment still determines the final value.

The early stub makes the strategy function name available before Atuin runs;
Atuin later replaces it. In autosuggestions 0.7.1, strategies are called when
fetching a suggestion, rather than permanently rejected at source time. The
stub is retained from the tested setup, but its necessity should be assessed
separately if initialization is changed.

### Widget wrapping

Autosuggestions wraps ZLE widgets to coordinate buffer changes with inline
suggestions. In 0.7.1, unclassified widgets take the `modify` path: save the
buffer/suggestion, clear `POSTDISPLAY`, call the original widget, then consider
fetching another suggestion. Widgets in `ZSH_AUTOSUGGEST_ACCEPT_WIDGETS` take
the `accept` path instead. This changes how the original Atuin TUI widget is
entered; the key binding alone does not show which wrapper runs around it.

Adding all six Atuin search widgets to the accept list was the retained fix
for the recorded Up-arrow regression. The array update is guarded so a shell
without autosuggestions does not fail. The plugin normally rebinds widgets on
`precmd`, so test in a fresh interactive shell with the complete initialization
sequence, including any syntax-highlighting or host-specific plugins.

On `air`, HM also orders Oh My Zsh and legacy local setup before program
integration. Keep Atuin initialization in the shared module; adding a second
`atuin init zsh` to the host module can change widget order.

## Verification

In a new interactive Zsh after the user runs `nhs`:

```sh
print -l "${ZSH_AUTOSUGGEST_STRATEGY[@]}"
print -l "${ZSH_AUTOSUGGEST_ACCEPT_WIDGETS[@]}" | rg atuin
bindkey '^[[A'
```

Expect `atuin`, `history`, `completion` in that order and all six Atuin search
widgets in the accept list. Test Up, Ctrl-R, and inline suggestions separately;
working Ctrl-R alone did not catch the original regression.

Inspect initialization without activation:

```sh
nix build --no-link --print-out-paths \
  '.#nixosConfigurations.briefcase.config.home-manager.users.inscripoem.home.file."./.zshrc".source'
```

Search the returned file for `atuin`, `AUTOSUGGEST`, and `autosuggestions` to
check ordering. Reassess these workarounds when upgrading the integrations, using a
fresh shell rather than sourcing `.zshrc` over already wrapped widgets.
