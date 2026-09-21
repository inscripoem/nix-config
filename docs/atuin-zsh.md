# Atuin and Zsh autosuggestions

[home/core/shell.nix](../home/core/shell.nix) integrates Atuin with
zsh-autosuggestions on Linux and Darwin. Up opens directory-scoped history,
Ctrl-R opens global history, and inline suggestions prefer Atuin with
history/completion fallbacks. Oh My Zsh is not required.

## Initialization order

| Order | Configuration | Reason |
|---|---|---|
| 540, Darwin only | Deduplicate PATH and add installed OrbStack completions to `fpath` | Make completions available before Home Manager runs `compinit` |
| 570, Home Manager | Completion initialization | Provide normal Zsh completion functions |
| 680 | Load `zsh/complist` and configure the native completion menu | Tab cycles candidates with a live preview |
| 700 | Source the Nix package's zsh-autosuggestions script | Load the plugin once, independently of the restricted HM strategy option |
| 1000, program integration | `atuin init zsh` | Define the Atuin strategy and search widgets |
| 1050 | Select `atuin history completion` and extend the accept-widget list | Apply the custom strategy after Atuin is available |
| 1200, Home Manager | Syntax highlighting | Load after the other interactive integrations |

The package is declared in `home.packages` and sourced explicitly. The
`programs.zsh.autosuggestion` integration is left disabled so it cannot source
another copy or assign a restricted built-in strategy list. No early Atuin
stub or host-specific initialization is needed.

The native menu keeps Git's branch order for checkout and displays completion
group headers. It uses `LS_COLORS` when available. There is no fzf-tab plugin;
fzf remains available through its independent Home Manager integration.

## Widget wrapping

Autosuggestions wraps ZLE widgets to coordinate buffer changes with inline
suggestions. The six Atuin widgets are added to
`ZSH_AUTOSUGGEST_ACCEPT_WIDGETS` after both integrations load. This preserves
the tested Up/Ctrl-R behavior; the key binding alone does not show the wrapper
that eventually handles it.

Keep Atuin initialization in the shared module. Adding another `atuin init zsh`
or sourcing `.zshrc` repeatedly can change the widget wrapping order.

## Verification

In a fresh interactive Zsh after the user runs `nhs`:

```sh
print -l "${ZSH_AUTOSUGGEST_STRATEGY[@]}"
print -l "${ZSH_AUTOSUGGEST_ACCEPT_WIDGETS[@]}" | rg atuin
bindkey '^[[A'
zstyle -L ':completion:*' menu
```

Expect `atuin`, `history`, `completion` in that order, all six Atuin search
widgets in the accept list, and `menu select`. Test Tab, Up, Ctrl-R, and inline
suggestions separately. Working Ctrl-R alone did not catch the original
Up-arrow regression.

Inspect initialization without activation:

```sh
nix build --no-link --print-out-paths \
  '.#nixosConfigurations.briefcase.config.home-manager.users.inscripoem.home.file."./.zshrc".source'
```

For `air`, use `darwinConfigurations.air` instead of
`nixosConfigurations.briefcase`. Search the returned file for `atuin`,
`AUTOSUGGEST`, and `autosuggestions` to check ordering. Reassess the integration
when upgrading its components, using a fresh shell rather than sourcing
`.zshrc` over already wrapped widgets.
