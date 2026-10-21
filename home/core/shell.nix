{ config, pkgs, lib, hostSpec ? { }, ... }:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  brewPrefix = if pkgs.stdenv.hostPlatform.isAarch64 then "/opt/homebrew" else "/usr/local";
  switchCommand = if isDarwin then
    "sudo -H darwin-rebuild switch --flake ${lib.escapeShellArg ".#${hostSpec.name}"} --show-trace"
  else
    "nh os switch -- --show-trace";
  shellAliases = lib.mapAttrs (_: value: lib.mkDefault value) ({
    nhs = switchCommand;
    nhsc = "${switchCommand} --max-jobs 0";
    ze = if isDarwin then "zed ." else "zeditor .";
  } // lib.optionalAttrs isDarwin {
    bs = "brew search";
    bic = "brew install --cask";
    bif = "brew install --formula";
    bu = "brew update && brew upgrade && brew cleanup";
  });
  darwinPaths = lib.unique ([
    "${config.home.profileDirectory}/bin"
    "${config.home.homeDirectory}/.nix-profile/bin"
  ] ++ config.home.sessionPath);

  # Run once per session so nested shells keep an activated project environment.
  # Bash also needs this in .bashrc when launched without a login .profile.
  darwinEnvironment = ''
    if [ -z "''${__NIX_CONFIG_DARWIN_ENV_SOURCED-}" ]; then
      if [ -x ${brewPrefix}/bin/brew ]; then
        eval "$(${brewPrefix}/bin/brew shellenv bash)"
      fi
      . "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh"

      # Nix owns the default toolchain; retain user tools and Homebrew afterwards.
      _darwin_remaining=${lib.escapeShellArg (lib.concatStringsSep ":" darwinPaths)}:"$PATH"
      PATH=
      while [ -n "$_darwin_remaining" ]; do
        _darwin_directory=''${_darwin_remaining%%:*}
        case "$_darwin_remaining" in
          *:*) _darwin_remaining=''${_darwin_remaining#*:} ;;
          *) _darwin_remaining= ;;
        esac
        case ":$PATH:" in
          *":$_darwin_directory:"*) ;;
          *) PATH="''${PATH:+$PATH:}$_darwin_directory" ;;
        esac
      done
      unset _darwin_remaining _darwin_directory
      export PATH
      export __NIX_CONFIG_DARWIN_ENV_SOURCED=1
    fi
  '';
in
{
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
  ] ++ lib.optionals isDarwin [
    "${config.home.homeDirectory}/.orbstack/bin"
  ];

  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = if isDarwin then ''
      ${darwinEnvironment}

      # macOS Bash 3.2 cannot load Home Manager's modern interactive setup.
      if [ "''${BASH_VERSINFO[0]}" -lt 4 ]; then
        return
      fi
    '' else ''
      export PATH="$PATH:$HOME/bin"
    '';
    profileExtra = lib.optionalString isDarwin darwinEnvironment;
    inherit shellAliases;
  };

  # zsh-autosuggestions is wired manually in initContent below instead of via
  # programs.zsh.autosuggestion: that option's `strategy` only accepts the
  # three built-in strategies and rejects "atuin", which would keep forcing
  # the integration into scattered mkBefore/mkAfter hacks.
  home.packages = [ pkgs.zsh-autosuggestions ];

  programs.zsh = {
    enable = true;
    dotDir = lib.mkIf isDarwin config.home.homeDirectory;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
    envExtra = lib.optionalString isDarwin ''
      if [[ ! -o login ]]; then
        ${darwinEnvironment}
      fi
    '';
    profileExtra = lib.optionalString isDarwin darwinEnvironment;

    history = {
      size = 100000;
      save = 100000;
      share = true;
      ignoreDups = true;
      ignoreAllDups = true;
      ignoreSpace = true;
      extended = true;
    };

    inherit shellAliases;

    initContent = lib.mkMerge [
      (lib.mkIf isDarwin (lib.mkOrder 540 ''
        typeset -gU PATH path
        if [[ -d "$HOME/.orbstack/shell/completions/zsh" ]]; then
          fpath+=("$HOME/.orbstack/shell/completions/zsh")
        fi
      ''))

      # Native completion menu (zsh/complist): Tab cycles candidates with
      # each highlighted one inserted live into the command line, and Return
      # accepts and executes.
      (lib.mkOrder 680 ''
        zmodload zsh/complist
        zstyle ':completion:*' menu select
        # keep git's own branch order for checkout
        zstyle ':completion:*:git-checkout:*' sort false
        # render group headers like [directory]
        zstyle ':completion:*:descriptions' format '[%d]'
        # colorize filename candidates (no-op when LS_COLORS is unset)
        zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}
      '')

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
    # HM's man-page completion generation costs one derivation per package
    # per lock bump (~80 per host); carapace and nix-index already cover
    # fish completions.
    generateCompletions = false;
    inherit shellAliases;
    shellInit = lib.optionalString isDarwin ''
      if not set -q __NIX_CONFIG_DARWIN_ENV_SOURCED
        if test -x ${brewPrefix}/bin/brew
          ${brewPrefix}/bin/brew shellenv fish | source
        end
        fish_add_path --path --move ${lib.escapeShellArgs darwinPaths}
        set -gx __NIX_CONFIG_DARWIN_ENV_SOURCED 1
      end
    '';
  };

  # fish.generateCompletions used to mkDefault this on; keep the apropos
  # index despite the switch. darwin still overrides it to false — pinned
  # fish manuals fail whatis parsing there (home/darwin/default.nix).
  programs.man.generateCaches = lib.mkDefault true;

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
