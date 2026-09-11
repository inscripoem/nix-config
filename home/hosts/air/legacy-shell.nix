{ config, lib, hostSpec, ... }:

let
  switchCommand = "sudo -H darwin-rebuild switch --flake ${lib.escapeShellArg ".#${hostSpec.name}"} --show-trace";
  rebuildAliases = {
    nhs = switchCommand;
    nhsc = "${switchCommand} --max-jobs 0";
    ze = "zed .";
  };
  preferHomeManager = ''
    export PATH="/etc/profiles/per-user/${config.home.username}/bin:$HOME/.nix-profile/bin:$PATH"
  '';
in
{
  # Transitional air-only setup. Migrate one tool at a time, removing its
  # manual initialization here when its Nix module takes ownership.
  programs.zsh = {
    shellAliases = rebuildAliases // {
      bic = "brew install --casks";
      bif = "brew install --formulae";
      bs = "brew search";
      bu = "brew update && brew upgrade && brew cleanup";
    };

    oh-my-zsh = {
      enable = true;
      # nix-index owns command_not_found_handler; do not load a second one.
      plugins = [ "git" "heroku" "pip" ];
      extraConfig = ''
        export DISABLE_AUTO_UPDATE="true"
      '';
    };

    envExtra = lib.mkBefore ''
      if [ -r "$HOME/.cargo/env" ]; then
        . "$HOME/.cargo/env"
      fi

      export ZEROBREW_DIR="$HOME/.zerobrew"
      export ZEROBREW_BIN="$ZEROBREW_DIR/bin"
      export ZEROBREW_ROOT=/opt/zerobrew
      export ZEROBREW_PREFIX=/opt/zerobrew
      export PKG_CONFIG_PATH="$ZEROBREW_PREFIX/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"

      if [ -f "$ZEROBREW_PREFIX/opt/ca-certificates/share/ca-certificates/cacert.pem" ]; then
        export CURL_CA_BUNDLE="$ZEROBREW_PREFIX/opt/ca-certificates/share/ca-certificates/cacert.pem"
        export SSL_CERT_FILE="$CURL_CA_BUNDLE"
      elif [ -f "$ZEROBREW_PREFIX/etc/ca-certificates/cacert.pem" ]; then
        export CURL_CA_BUNDLE="$ZEROBREW_PREFIX/etc/ca-certificates/cacert.pem"
        export SSL_CERT_FILE="$CURL_CA_BUNDLE"
      elif [ -f "$ZEROBREW_PREFIX/share/ca-certificates/cacert.pem" ]; then
        export CURL_CA_BUNDLE="$ZEROBREW_PREFIX/share/ca-certificates/cacert.pem"
        export SSL_CERT_FILE="$CURL_CA_BUNDLE"
      fi

      if [ -d "$ZEROBREW_PREFIX/etc/ca-certificates" ]; then
        export SSL_CERT_DIR="$ZEROBREW_PREFIX/etc/ca-certificates"
      elif [ -d "$ZEROBREW_PREFIX/share/ca-certificates" ]; then
        export SSL_CERT_DIR="$ZEROBREW_PREFIX/share/ca-certificates"
      fi

      for _air_bin in "$ZEROBREW_BIN" "$ZEROBREW_PREFIX/bin"; do
        case ":$PATH:" in
          *":$_air_bin:"*) ;;
          *) export PATH="$_air_bin:$PATH" ;;
        esac
      done
      unset _air_bin
    '';

    profileExtra = ''
      if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi
      if [ -r "$HOME/.orbstack/shell/init.zsh" ]; then
        source "$HOME/.orbstack/shell/init.zsh"
      fi
      if [ -r "$HOME/.rye/env" ]; then
        source "$HOME/.rye/env"
      fi

      ${preferHomeManager}
      typeset -U path
    '';

    # OMZ (order 800) must provide compdef before legacy completions load;
    # default-priority integrations (1000) and syntax highlighting (1200)
    # still run after this block.
    initContent = lib.mkOrder 900 ''
      export NVM_DIR="$HOME/.nvm"
      if [ -s "$NVM_DIR/nvm.sh" ]; then
        . "$NVM_DIR/nvm.sh"
      fi
      if [ -s "$NVM_DIR/bash_completion" ]; then
        . "$NVM_DIR/bash_completion"
      fi

      export BUN_INSTALL="$HOME/.bun"
      if [ -s "$BUN_INSTALL/_bun" ]; then
        source "$BUN_INSTALL/_bun"
      fi
      export PATH="$BUN_INSTALL/bin:$PATH"

      if command -v go >/dev/null 2>&1; then
        _air_gopath="$(go env GOPATH 2>/dev/null)"
        if [ -n "$_air_gopath" ]; then
          export PATH="$_air_gopath/bin:$PATH"
        fi
        unset _air_gopath
      fi

      if [ -r "$HOME/.local/bin/env" ]; then
        . "$HOME/.local/bin/env"
      fi
      export PATH="$HOME/.moon/bin:$PATH"
      export PROTO_HOME="$HOME/.proto"
      export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"
      export PATH="$HOME/.claude/bin:$PATH"

      ${preferHomeManager}
    '';
  };

  programs.fish.shellAliases = rebuildAliases;

  programs.bash = {
    bashrcExtra = ''
      if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi
      if [ -r "$HOME/.local/bin/env" ]; then
        . "$HOME/.local/bin/env"
      fi
      if [ -r "$HOME/.cargo/env" ]; then
        . "$HOME/.cargo/env"
      fi
      ${preferHomeManager}
    '';
    profileExtra = ''
      export PATH="$PATH:$HOME/.tools"
      if [ -r "$HOME/.rye/env" ]; then
        . "$HOME/.rye/env"
      fi
      if [ -r "$HOME/.local/bin/env" ]; then
        . "$HOME/.local/bin/env"
      fi
      if [ -r "$HOME/.cargo/env" ]; then
        . "$HOME/.cargo/env"
      fi
    '';
  };
}
