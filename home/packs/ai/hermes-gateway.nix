{ config, lib, pkgs, hermes-agent, ... }:

let
  cfg = config.packs.ai;

  # Official upstream package (full dependency set): feishu SDK, tirith and
  # locales are preinstalled, and the wrapper already suffixes the complete
  # runtime toolchain (rg/git/ssh/ffmpeg/tirith/clipboard + node+npm), so no
  # PATH override is needed here.
  hermesPkg = hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Runtime interpreter of hermesPkg. `bin/python3` does not exist in the
  # wrapper package — the interpreter lives in the sealed venv that the
  # wrapper exports as HERMES_PYTHON and execs `hermes` from. Upstream
  # exposes that same venv as passthru.hermesVenv, so it can be referenced
  # at evaluation time without reading the wrapper (no IFD).
  hermesPython = hermesPkg.passthru.hermesVenv;
in
{
  options.packs.ai.hermes-agent = {
    # Opt-in extra, not part of the pack bundle: unlike the members above it
    # defaults to false and is enabled per host in home/hosts/<host>.nix
    # (currently briefcase only). Promote to `default = cfg.enable` if it
    # ever becomes standard issue.
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "hermes-agent CLI (Nous Research), opt-in per host";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.hermes-agent.enable {
      # Official upstream flake package; state lives in ~/.hermes. Upstream
      # does not seal runtime lazy installs: a missing dep attempts a pip
      # install into the read-only store and fails cleanly. The durable
      # target set on the gateway unit below gives them a working escape
      # hatch instead.
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
    #
    # Consequence of declaring the unit (observed 2026-10-28): the CLI calls
    # refresh_systemd_unit_if_needed() from start/restart/install-repair
    # (hermes_cli/gateway.py:3588, :3715, :3741) and rewrites the unit
    # whenever its text differs from generate_systemd_unit(). This path is a
    # symlink into the read-only store, so that write raises OSError EROFS
    # and aborts `hermes gateway start|restart` before systemctl is reached.
    # Text parity is not a way out: the generated template captures the
    # *invoking* environment (observed: an extra LD_LIBRARY_PATH= line when
    # generated from the DSH desktop), so the comparison target moves with
    # whoever runs the CLI. Drive this unit with `systemctl --user`, or with
    # `nhs`, whose sd-switch step reloads and restarts changed units; the
    # read-only verbs (`hermes gateway status`, `logs`, `config`) still work.
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
          # An unclean shutdown (drain SIGKILL, hard power-off) can leave
          # gateway-locks/host-gateway.json pinning a dead PID; every later
          # start then refuses to take the host over ("already owns this
          # host", exit 75) because the dead PID's control socket never
          # answers — a permanent crash loop (2026-10-24: 5281 restarts).
          # A live gateway holds an flock on host-gateway.lock, so a free
          # lock proves the record is stale and safe to drop.
          ExecStartPre = pkgs.writeShellScript "hermes-gateway-clear-stale-record" ''
            stateLocks="''${XDG_STATE_HOME:-$HOME/.local/state}/hermes/gateway-locks"
            record="$stateLocks/host-gateway.json"
            lock="$stateLocks/host-gateway.lock"
            if [ -f "$record" ] && ${pkgs.util-linux}/bin/flock -n "$lock" true; then
              rm -f -- "$record"
            fi
          '';
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
          # to signal a non-retryable failure. 75 is also a *successful*
          # exit, as in upstream's template: without it an in-band /restart
          # leaves Result=exit-code behind, `systemctl --user is-failed`
          # reports true, and `hermes gateway status` warns that the restart
          # is "stuck in systemd failed state (exit 75)"
          # (hermes_cli/gateway.py:3894) until someone runs reset-failed.
          # RestartForceExitStatus still forces the respawn, so the two
          # options do not conflict.
          SuccessExitStatus = 75;
          RestartForceExitStatus = 75;
          RestartPreventExitStatus = 78;
          # ExecStop only records a planned stop, mirroring upstream's own
          # unit: the marker script returns immediately, then systemd sends
          # KillSignal=SIGTERM and the gateway's signal handler drains (2s
          # observed). Never call `hermes gateway stop` here — that CLI runs
          # `systemctl --user stop hermes-gateway.service` itself
          # (hermes_cli/gateway.py:3726), so the inner stop steals the outer
          # restart job ("Job canceled") while the unit waits on an ExecStop
          # that is waiting on the unit: a deadlock that burns the whole
          # TimeoutStopSec below and ends in Result: timeout with the gateway
          # left stopped (2026-10-28). The marker carries PID + start time,
          # so a leftover file cannot mislabel an unrelated later start.
          #
          # A system shutdown stops the user session and the network in
          # parallel, so the drain can never deliver anything there; while
          # the system manager is already stopping, kill the daemon
          # outright instead. The ExecStartPre flock check clears the
          # stale host record this leaves on next start.
          ExecStop = "-${pkgs.writeShellScript "hermes-gateway-stop" ''
            state="$(${pkgs.systemd}/bin/systemctl is-system-running 2>/dev/null)" || true
            if [ "$state" = stopping ]; then
              kill -KILL "$MAINPID" 2>/dev/null || true
              exit 0
            fi
            # Upstream's ExecStop module: HERMES_HOME comes from the unit
            # environment, $MAINPID from systemd. Runs in the sealed venv
            # because the wrapper package ships no interpreter.
            exec ${hermesPython}/bin/python3 -I -m gateway.systemd_stop_mark
          ''}";
          # Upstream parity: SIGKILL whatever helper the gateway left behind
          # in the unit cgroup (MCP bridges, platform daemons) so a restart
          # cannot be blocked by an orphan holding a socket or lock. Refuses
          # when a live gateway is still in the cgroup, so it can never kill
          # the running daemon; `-` keeps a failure from masking the stop.
          ExecStopPost = "-${hermesPython}/bin/python3 -I -m gateway.cgroup_cleanup";
          # Upstream parity (their template uses a bare /bin/kill): the
          # gateway's handler turns SIGUSR1 into a drain-aware restart —
          # active turns finish, the process exits, Restart=always respawns
          # it (gateway/run.py:4837). Without this line `systemctl --user
          # reload` is refused and the only way to bounce the gateway is a
          # hard stop.
          ExecReload = "${pkgs.util-linux}/bin/kill -USR1 $MAINPID";
          KillMode = "mixed";
          KillSignal = "SIGTERM";
          # Upstream floor: drain (180s) + cron_drain (30s); below it the
          # gateway warns of a mid-drain SIGKILL (gateway/run_startup.py:1003).
          TimeoutStopSec = 210;
          StandardOutput = "journal";
          StandardError = "journal";
        };
      };
    })
  ];
}
