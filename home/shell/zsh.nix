{ lib, ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;

    autosuggestion = {
      enable = true;
      # Intentionally empty so home-manager skips emitting
      # `ZSH_AUTOSUGGEST_STRATEGY=...`. We set it ourselves in `initContent`
      # below because home-manager's `strategy` option only accepts
      # "history" | "completion" | "match_prev_cmd" and rejects "atuin".
      strategy = [ ];
    };

    history = {
      size = 100000;
      save = 100000;
      share = true;
      ignoreDups = true;
      ignoreAllDups = true;
      ignoreSpace = true;
      extended = true;
    };

    shellAliases = {
      nhs = "nh os switch -- --show-trace";
      # Cache-only rebuild: --max-jobs 0 forbids local builds, so any cache
      # miss aborts before mutating the system. Pair with `git checkout
      # flake.lock` to roll back a `nix flake update` that outran upstream
      # binary caches.
      nhsc = "nh os switch -- --show-trace --max-jobs 0";
      ze = "zeditor .";
    };

    initContent = lib.mkMerge [
      # Declare an empty `_zsh_autosuggest_strategy_atuin` BEFORE
      # zsh-autosuggestions is sourced, so its startup does not fail with
      # "function not found" when it sees the "atuin" entry in
      # ZSH_AUTOSUGGEST_STRATEGY. `atuin init zsh` later overrides this stub
      # with the real implementation.
      (lib.mkBefore ''
        _zsh_autosuggest_strategy_atuin() { :; }
      '')

      # Run AFTER `atuin init zsh`:
      # 1) Set atuin as the preferred ghost-text strategy (history/completion
      #    as fallback). Done here because home-manager's `strategy` option
      #    rejects "atuin" (see comment above).
      # 2) Whitelist atuin's widgets in ZSH_AUTOSUGGEST_ACCEPT_WIDGETS so
      #    pressing Up / Ctrl-R is not swallowed by autosuggestions' default
      #    clear-on-unknown-widget behaviour, and reaches atuin's TUI.
      (lib.mkAfter ''
        ZSH_AUTOSUGGEST_STRATEGY=(atuin history completion)
        if typeset -p ZSH_AUTOSUGGEST_ACCEPT_WIDGETS >/dev/null 2>&1; then
          ZSH_AUTOSUGGEST_ACCEPT_WIDGETS+=(
            atuin-search atuin-search-vicmd atuin-search-viins
            atuin-up-search atuin-up-search-vicmd atuin-up-search-viins
          )
        fi
      '')
    ];
  };
}
