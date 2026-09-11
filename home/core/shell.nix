{ pkgs, lib, ... }:

{
  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"
    '';
    shellAliases = {
    };
  };

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
      nhs = lib.mkDefault "nh os switch -- --show-trace";
      # Cache-only rebuild: --max-jobs 0 forbids local builds, so any cache
      # miss aborts before mutating the system. Pair with `git checkout
      # flake.lock` to roll back a `nix flake update` that outran upstream
      # binary caches.
      nhsc = lib.mkDefault "nh os switch -- --show-trace --max-jobs 0";
      ze = lib.mkDefault "zeditor .";
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

  programs.fish = {
    enable = true;
    shellAliases = {
      nhs = lib.mkDefault "nh os switch -- --show-trace";
      # Cache-only rebuild: --max-jobs 0 forbids local builds, so any cache
      # miss aborts before mutating the system. Pair with `git checkout
      # flake.lock` to roll back a `nix flake update` that outran upstream
      # binary caches.
      nhsc = lib.mkDefault "nh os switch -- --show-trace --max-jobs 0";
      ze = lib.mkDefault "zeditor .";
    };
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };

  programs.bat = {
    enable = true;
    config.theme = "Catppuccin Macchiato";
    themes."Catppuccin Macchiato" = {
      src = pkgs.fetchFromGitHub {
        owner = "catppuccin";
        repo = "bat";
        rev = "6810349b28055dce54076712fc05fc68da4b8ec0";
        hash = "sha256-lJapSgRVENTrbmpVyn+UQabC9fpV1G1e+CdlJ090uvg=";
      };
      file = "themes/Catppuccin Macchiato.tmTheme";
    };
  };

  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    shellWrapperName = "y";
  };

  programs.atuin = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    settings = {
      auto_sync = false;
      update_check = false;
      style = "compact";
      inline_height = 0;
      show_preview = true;
      filter_mode = "global";
      filter_mode_shell_up_key_binding = "directory";
      search_mode = "fuzzy";
      enter_accept = true;
    };
  };

  programs.tealdeer = {
    enable = true;
    settings = {
      display = {
        compact = false;
        use_pager = false;
      };
      updates = {
        auto_update = true;
        auto_update_interval_hours = 168;
      };
    };
  };

  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    # Atuin already owns Ctrl-R; disable fzf's history widget to avoid the
    # conflict warning.
    historyWidget.command = "";
  };

  programs.eza = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };

  programs.carapace = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  # SOPS needs to know where the editor's age private key lives so
  # `sops secrets/...` can decrypt files for editing. The key itself
  # lives at ~/.config/sops/age/keys.txt and is NEVER committed to
  # git. See docs/secrets.md §2.
  home.sessionVariables.SOPS_AGE_KEY_FILE = "$HOME/.config/sops/age/keys.txt";
}
