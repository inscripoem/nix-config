{ config, lib, pkgs, llm-agents, ... }:
let
  cfg = config.packs.ai;
  agentPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # Hermes wrapper PATH: mirrors the official flake's runtimeDeps minus node
  # (llm-agents already prefixes it) and tirith (self-bootstrapped into
  # ~/.hermes/bin and referenced by config.yaml). llm-agents only prefixes
  # node, so launches outside a login shell (GUI launchers, the gateway
  # service) would otherwise miss rg/git/ssh entirely.
  hermesPkg = agentPkgs.hermes-agent.overrideAttrs (old: {
    makeWrapperArgs = (old.makeWrapperArgs or [ ]) ++ [
      "--prefix"
      "PATH"
      ":"
      (lib.makeBinPath [
        pkgs.ripgrep
        pkgs.git
        pkgs.openssh
        pkgs.ffmpeg
        pkgs.wl-clipboard
        pkgs.xclip
      ])
    ];
  });
in {
  options.packs.ai = {
    enable = lib.mkEnableOption "AI CLI toolchain (aichat + llm-agents.*)";

    aichat.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "aichat — TUI chat client";
    };

    opencode.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "opencode agent CLI";
    };

    antigravity-cli.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "antigravity-cli";
    };

    ck.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "ck agent CLI";
    };

    claude-code.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "claude-code CLI";
    };

    codex.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "codex CLI";
    };

    rtk.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "rtk CLI";
    };

    zcode.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "zcode CLI";
    };

    # Opt-in extra, not part of the pack bundle: unlike the members above it
    # defaults to false and is enabled per host in home/hosts/<host>.nix
    # (currently briefcase only). Promote to `default = cfg.enable` if it
    # ever becomes standard issue.
    hermes-agent.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "hermes-agent CLI (Nous Research), opt-in per host";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.aichat.enable {
      programs.aichat.enable = true;
    })

    (lib.mkIf cfg.opencode.enable {
      home.packages = [ agentPkgs.opencode ];
      # Required by oh-my-opencode-slim's Orchestrator to dispatch specialists
      # as background tasks. opencode reads it at startup; its own installer
      # tries to patch ~/.zshrc, which is a read-only nix-store symlink on
      # NixOS, so we declare it here so every shell and any GUI launcher
      # (KDE menu, krunner, IDE) sees the same value.
      home.sessionVariables.OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS = "true";
    })

    (lib.mkIf cfg.antigravity-cli.enable {
      home.packages = [ agentPkgs.antigravity-cli ];
    })

    (lib.mkIf cfg.ck.enable {
      home.packages = [ agentPkgs.ck ];
    })

    (lib.mkIf cfg.claude-code.enable {
      home.packages = [ agentPkgs.claude-code ];
    })

    (lib.mkIf cfg.codex.enable {
      home.packages = [ agentPkgs.codex ];
    })

    (lib.mkIf cfg.rtk.enable {
      home.packages = [ agentPkgs.rtk ];
    })

    (lib.mkIf cfg.zcode.enable {
      home.packages = [ agentPkgs.zcode ];

      # ZCode is an Electron app that calls setAsDefaultProtocolClient() on
      # every launch, rewriting a user-level desktop file into
      # ~/.local/share/applications/zcode.desktop. That copy shadows the one
      # shipped by the package and breaks xdg-desktop-portal's registration of
      # x-scheme-handler/zcode — after the browser OAuth redirect the portal
      # then shows an empty "Open With" dialog ("no available apps"). Register
      # the scheme via [Added Associations]: GLib only enumerates schemes
      # listed there, and this tweak path is immune to the desktop-file
      # shadowing.
      xdg.dataFile."applications/mimeapps.list".text = ''
        [Added Associations]
        x-scheme-handler/zcode=zcode.desktop;
      '';
    })

    (lib.mkIf cfg.hermes-agent.enable {
      # Sealed nix package: runtime pip/npm self-install and `hermes update`
      # are patched out by llm-agents.nix; state lives in ~/.hermes.
      home.packages = [ hermesPkg ];
    })

    # Declarative replacement for the gateway unit that `hermes gateway
    # install` generates: its template ExecStart is a bare `python -m
    # hermes_cli.main` that crash-loops under Nix, and the running gateway
    # rewrites the unit file, so hand edits require a drop-in. This unit
    # routes through the wrapper and carries the full agent toolchain on
    # PATH. Deliberately no HERMES_MANAGED — config.yaml stays
    # runtime-editable (that write-lock is the official HM module's managed
    # mode, which we chose not to adopt).
    (lib.mkIf (cfg.hermes-agent.enable && pkgs.stdenv.hostPlatform.isLinux) {
      systemd.user.services.hermes-gateway = {
        Unit = {
          Description = "Hermes Agent Gateway - Messaging Platform Integration";
          # network-online.target is a system target; a user unit can only
          # meaningfully order after default.target.
          After = [ "default.target" ];
          StartLimitIntervalSec = 0;
        };
        Install.WantedBy = [ "default.target" ];
        Service = {
          Type = "simple";
          ExecStart = "${hermesPkg}/bin/hermes gateway run";
          WorkingDirectory = "${config.home.homeDirectory}/.hermes";
          Environment = [
            # Agent terminal-session toolchain. The HM user profile carries
            # rg/jq/fd/gh/uv, the system profile grep/find/curl, plus the
            # nix CLI and flatpak. /run/wrappers/bin (setuid) is excluded
            # on purpose.
            "PATH=${hermesPkg}/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:${config.home.homeDirectory}/.local/share/flatpak/exports/bin:/var/lib/flatpak/exports/bin:${config.home.homeDirectory}/.local/bin:/usr/local/bin:/usr/bin:/bin"
            # Feishu SDK (lark-oapi) lives outside the sealed store in the
            # durable lazy-install target; removing this disconnects feishu.
            "HERMES_LAZY_INSTALL_TARGET=${config.home.homeDirectory}/.hermes/lazy-packages"
            "HERMES_HOME=${config.home.homeDirectory}/.hermes"
            "HERMES_SUPERVISED_CHILD=1"
          ];
          Restart = "always";
          RestartSec = 5;
          # hermes gateway exits 75 to request an immediate restart and 78
          # to signal a non-retryable failure.
          RestartForceExitStatus = 75;
          RestartPreventExitStatus = 78;
          KillMode = "mixed";
          KillSignal = "SIGTERM";
          TimeoutStopSec = 210;
          StandardOutput = "journal";
          StandardError = "journal";
        };
      };
    })
  ];
}
