{ config, lib, pkgs, llm-agents, hermes-agent, passwordStore, ... }:
let
  cfg = config.packs.ai;
  agentPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # Official upstream package (full dependency set): feishu SDK, tirith and
  # locales are preinstalled, and the wrapper already suffixes the complete
  # runtime toolchain (rg/git/ssh/ffmpeg/tirith/clipboard + node+npm), so no
  # PATH override is needed here.
  hermesPkg = hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # The overridden derivation must be the ONLY workbuddy in the module: the
  # menu entry (home.packages) and the autostart desktop file both reference
  # it, so the generation closure keeps a single copy and autostart launches
  # the same wrapper with --password-store. Referencing the base pkgs.workbuddy
  # anywhere would pull a second, flag-less copy into the closure.
  workbuddyPkg = pkgs.workbuddy.override {
    commandLineArgs = "--password-store=${passwordStore}";
  };

  # The desktop app keeps its binary but the terminal `zcode` name moves to
  # pkgs.zcode-cli (official open-source CLI, built from source): the
  # desktop-bundled glm/zcode.cjs cannot run its TUI upstream — the
  # distribution does not ship @zcode/tui. The GUI launcher becomes
  # `zcode-desktop`, keeping the original wrapper's xdg/ozone/IME flags,
  # and the shipped zcode.desktop Exec is repointed at it because it
  # hardcodes `zcode`. Paths assume the Linux deb layout; only Linux hosts
  # enable packs.ai.zcode (air does not). Update tracks are decoupled:
  # desktop via the llm-agents input, CLI via update-versions.sh.
  zcodePkg = pkgs.symlinkJoin {
    # Stable name (no version): generation diff tools pair by package name
    # and would render a version bump as remove+add instead of a change.
    # The version stays queryable via the forwarded upstream passthru.
    name = "zcode-desktop-joined";
    paths = [ agentPkgs.zcode ];
    postBuild = ''
      mv $out/bin/zcode $out/bin/zcode-desktop
      rm $out/share/applications/zcode.desktop
      sed 's|^Exec=zcode|Exec=zcode-desktop|' \
        ${agentPkgs.zcode}/share/applications/zcode.desktop \
        > $out/share/applications/zcode.desktop
    '';
  };
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

    # Opt-in extra: Alibaba's new-form agentic desktop app — the GUI
    # counterpart to the CLI agents above, distinct from the qoder-cn-ide
    # editor that lives in desktop.editors-gui.
    "qoder-cn".enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "qoder-cn agentic desktop app (Alibaba), opt-in per host";
    };

    # Opt-in extra: Tencent CodeBuddy team's agentic desktop workspace.
    # Single Linux build (no CN/international split on Linux); the same
    # package serves both account regions.
    workbuddy.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "workbuddy agentic desktop app (Tencent), opt-in per host";
    };

    # Opt-in extra: Orca (onorca.dev), Stably AI's open-source Agent
    # Development Environment — orchestrates parallel CLI agents, each in
    # its own git worktree. Same "bring your own agent" model as the CLIs
    # above, so it belongs in this pack rather than desktop.editors-gui.
    orca.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "orca-ide agentic desktop app (Stably AI), opt-in per host";
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
      home.packages = [
        zcodePkg
        pkgs.zcode-cli
      ];

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
      # Official upstream flake package; state lives in ~/.hermes. Upstream
      # does not seal runtime lazy installs: a missing dep attempts a pip
      # install into the read-only store and fails cleanly. The durable
      # target set on the gateway unit below gives them a working escape
      # hatch instead.
      home.packages = [ hermesPkg ];
    })

    (lib.mkIf cfg."qoder-cn".enable {
      home.packages = [
        (pkgs.qoder-cn.override {
          commandLineArgs = "--password-store=${passwordStore}";
        })
      ];
    })

    (lib.mkIf cfg.workbuddy.enable {
      home.packages = [ workbuddyPkg ];
      # XDG autostart (same pattern as 1password/desktop-env): reference the
      # shipped desktop entry whose Exec already points at this generation's
      # wrapper, so HM re-points it on every switch and it never goes stale.
      # Do NOT use the app's own "auto launch" toggle: setLoginItemSettings
      # bakes the current store path into ~/.config/autostart, which breaks
      # after a GC, or falls back to the raw Electron binary (no sandbox
      # flags, no bwrap/socat on PATH).
      xdg.configFile."autostart/workbuddy.desktop".source =
        "${workbuddyPkg}/share/applications/workbuddy.desktop";

      # The agent sandbox replaces PATH wholesale (vendored safe-bin + managed
      # node/python) and its Rust sandbox-center exposes no env hook: the
      # CLI-side CODEBUDDY_ENV_FILE / WORKBUDDY_EXTRA_PATHS hooks are never
      # consumed on this path (verified 10-11 via sandbox logs and strings on
      # the sandbox-center binary). Non-interactive zsh always sources
      # ~/.zshenv though, so appending the host dirs there is the only layer
      # that reaches inside the bwrap sandbox (which ro-binds / anyway).
      # Appending keeps safe-bin's rm/rmdir/unlink shims ahead of GNU
      # coreutils; /run/wrappers/bin is excluded on purpose (same rule as the
      # hermes-gateway unit below).
      programs.zsh.envExtra = lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
        export PATH="$PATH:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin"
      '';
    })

    (lib.mkIf cfg.orca.enable {
      home.packages = [ pkgs.orca-ide ];
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
            # Durable lazy-install target (the Docker-image escape hatch).
            # The official package preinstalls feishu/lark-oapi, so this is
            # no longer load-bearing — it only catches deps missing from
            # upstream's `full` set (e.g. the ddgs web-search backend).
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
          # SIGTERM drains in-flight agent turns and can outlast any generous
          # timeout (210s still ended in SIGKILL while blocking, and failing,
          # the whole home-manager activation). ExecStop takes the upstream
          # CLI path: it marks a planned stop, spends its own 90s client
          # bound, and the remainder of the 150s budget stays for a clean
          # drain before systemd escalates to SIGKILL.
          ExecStop = "${hermesPkg}/bin/hermes gateway stop";
          KillMode = "mixed";
          KillSignal = "SIGTERM";
          TimeoutStopSec = 150;
          StandardOutput = "journal";
          StandardError = "journal";
        };
      };
    })
  ];
}
