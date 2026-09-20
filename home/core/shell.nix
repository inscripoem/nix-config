{ config, lib, pkgs, ... }:

{
  # fzf-tab's load order is a hard upstream requirement: after compinit,
  # before widget-wrapping plugins like zsh-autosuggestions. The order is
  # enforced only by the mkOrder values in initContent below, so assert the
  # resulting layout -- an HM upgrade that shifts those blocks fails the
  # build here instead of silently breaking Tab completion. builtins.match
  # needs a single line (hence the flattening) and .* is order-sensitive.
  # Checked only when fzf-tab is actually enabled: on air, OMZ runs
  # compinit internally and the string never appears in initContent.
  assertions = [
    {
      assertion =
        let zshInit = lib.replaceStrings [ "\n" ] [ " " ] config.programs.zsh.initContent;
            hasFzfTab = builtins.match ".*fzf-tab.plugin.zsh.*" zshInit != null;
        in !hasFzfTab || builtins.match ".*compinit.*fzf-tab.*zsh-autosuggestions.*" zshInit != null;
      message = "zsh: expected load order compinit -> fzf-tab -> zsh-autosuggestions (home-manager init order changed?)";
    }
  ];

  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"
    '';
    shellAliases = {
    };
  };

  # zsh-autosuggestions is wired manually in initContent below instead of via
  # programs.zsh.autosuggestion: that option's `strategy` only accepts the
  # three built-in strategies and rejects "atuin", which would keep forcing
  # the integration into scattered mkBefore/mkAfter hacks.
  home.packages = [ pkgs.zsh-autosuggestions ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;

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
      # Render completion candidates in an fzf UI; data sources (compinit,
      # carapace) are untouched. Must source AFTER compinit (home-manager
      # order 570) but BEFORE zsh-autosuggestions (order 700 below), which
      # wraps widgets -- see fzf-tab README, "Install"; not via
      # programs.zsh.plugins, which offers no ordering control. The
      # assertion at the top of this file fails the build if an HM upgrade
      # breaks this order.
      #
      # Linux-only for now: air still boots zsh through oh-my-zsh, whose
      # compinit fires inside the OMZ block at order 800 -- after 680 here,
      # and there is no order slot that can satisfy fzf-tab while OMZ stays.
      # Drop the mkIf when air's legacy shell setup is retired.
      (lib.mkIf (!pkgs.stdenv.hostPlatform.isDarwin) (lib.mkOrder 680 ''
        source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh

        # Recommended setup from the fzf-tab README ("Configure"):
        # keep git's own branch order for checkout
        zstyle ':completion:*:git-checkout:*' sort false
        # render group headers like [directory]; enables F1/F2 group switching
        zstyle ':completion:*:descriptions' format '[%d]'
        # colorize filename candidates (no-op when LS_COLORS is unset)
        zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}
        # suppress the native menu so fzf-tab captures the unambiguous prefix
        zstyle ':completion:*' menu no
        # preview the candidate directory with eza while completing cd
        zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
        # fzf treats Tab as multi-select toggle; rebind it to accept the
        # highlighted candidate so Tab still fills in the completion the way
        # the native menu did, and Enter keeps meaning "run the command"
        zstyle ':fzf-tab:*' fzf-flags --bind=tab:accept
      ''))

      # Sourced WITHOUT ZSH_AUTOSUGGEST_STRATEGY set: on startup the plugin
      # validates every entry in that variable, and "atuin" would fail with
      # "function not found". atuin's init (order 1000, below) injects the
      # real strategy function; the variable is set at 1050.
      (lib.mkOrder 700 ''
        source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
      '')

      # Runs after `atuin init zsh`, which injects the real
      # `_zsh_autosuggest_strategy_atuin`:
      # 1) atuin as the preferred ghost-text strategy (history/completion
      #    as fallback).
      # 2) Whitelist atuin's widgets in ZSH_AUTOSUGGEST_ACCEPT_WIDGETS so
      #    Up / Ctrl-R reach atuin's TUI instead of being swallowed by
      #    autosuggestions' clear-on-unknown-widget behaviour. The array
      #    exists by now -- autosuggestions created it when sourced at 700.
      (lib.mkOrder 1050 ''
        ZSH_AUTOSUGGEST_STRATEGY=(atuin history completion)
        ZSH_AUTOSUGGEST_ACCEPT_WIDGETS+=(
          atuin-search atuin-search-vicmd atuin-search-viins
          atuin-up-search atuin-up-search-vicmd atuin-up-search-viins
        )
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
