{ config, lib, pkgs, llm-agents, ... }:

let
  cfg = config.packs.ai;
  agentPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # Single-copy rule (same as workbuddyPkg): home.packages and the runtime
  # service must resolve to one derivation. The build logic — the asar
  # patches and, for now, the autostart wrapper/template — lives in
  # pkgs/orca.nix; version bumps ride llm-agents flake updates, no
  # update-versions.sh section needed.
  orcaPkg = pkgs.callPackage ../../../pkgs/orca.nix { orca = agentPkgs.orca; };
in
{
  options.packs.ai.orca = {
    # Opt-in extra: Orca (onorca.dev), Stably AI's open-source Agent
    # Development Environment — orchestrates parallel CLI agents, each in
    # its own git worktree. Same "bring your own agent" model as the CLIs
    # above, so it belongs in this pack rather than desktop.editors-gui.
    # Taken from the llm-agents input (deb-based build); version bumps ride
    # flake updates instead of update-versions.sh. The Linux build carries
    # local asar patches (upstream gates all tray plumbing on win32/darwin):
    # close-to-tray and the silent-start env gate; their regex anchors live
    # in pkgs/orca-patch.py and fail the build when an llm-agents update
    # refactors one of the patched sites. `autostart` no longer uses them —
    # once `orca serve` has proven itself, the five patches, orca-patch.py,
    # bin/orca-autostart and the autostart template can all be retired.
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "orca agentic desktop app (Stably AI), opt-in per host";
    };

    # Start the headless Orca runtime at login (Linux): `orca serve` owns
    # the server, terminal daemon and agents, so no window and no tray
    # process is needed and closing the UI only closes the window. The unit
    # mirrors what `orca serve service install` writes upstream
    # (serve-service-unit.ts) — including KillMode=process, which stops the
    # supervisor while leaving the terminal daemon alive.
    autostart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "start the headless orca runtime at login (Linux only)";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.orca.enable {
      home.packages = [ orcaPkg ];
    })

    (lib.mkIf (cfg.orca.enable && cfg.orca.autostart && pkgs.stdenv.hostPlatform.isLinux) {
      systemd.user.services.orca-serve = {
        Unit = {
          Description = "Orca server (orca serve --supervise)";
          StartLimitIntervalSec = 900;
          StartLimitBurst = 5;
        };
        Service = {
          Type = "simple";
          # bin/orca is the CLI entry point. bin/orca-ide carries our Wayland
          # IME flags, which are meaningless for a headless run.
          ExecStart = "${orcaPkg}/bin/orca serve --supervise --no-pairing";
          Environment = [ "ORCA_USER_DATA_PATH=%h/.config/orca" ];
          KillMode = "process";
          Restart = "on-failure";
          RestartSec = 10;
          TimeoutStopSec = 90;
        };
        Install.WantedBy = [ "default.target" ];
      };
    })
  ];
}
