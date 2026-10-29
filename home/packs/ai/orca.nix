{ config, lib, pkgs, llm-agents, ... }:

let
  cfg = config.packs.ai;
  agentPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # Single-copy rule (same as workbuddyPkg): home.packages and the
  # autostart desktop file must resolve to one derivation. The build
  # logic — both asar patches, the autostart wrapper and its desktop
  # template — lives in pkgs/orca-patched.nix; version bumps ride
  # llm-agents flake updates, no update-versions.sh section needed.
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
    # two local asar patches (upstream gates all tray plumbing on
    # win32/darwin): close-to-tray and the silent-start env gate; their
    # anchors live in pkgs/orca-tray.py and pkgs/orca-silent-start.py and
    # fail the build when an llm-agents update reshuffles the asar.
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "orca agentic desktop app (Stably AI), opt-in per host";
    };

    # Autostart orca silently to tray at login (Linux): an XDG autostart
    # entry runs bin/orca-autostart, which sets ORCA_SILENT_START=1 for the
    # asar gate — no window, daemon and tray up, agents one tray-click away.
    # Ordered after dms.service by the app-@autostart drop-in
    # (home/desktop/niri/default.nix), so
    # the tray icon registers against a live StatusNotifierWatcher.
    autostart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "autostart orca silently to tray at login (Linux only)";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.orca.enable {
      home.packages = [ orcaPkg ];
    })

    (lib.mkIf (cfg.orca.enable && cfg.orca.autostart && pkgs.stdenv.hostPlatform.isLinux) {
      # Same single-copy rule as workbuddy's autostart entry
      # (ai/workbuddy.nix): point autostart at the patched derivation's template instead
      # of referencing a store path that GC would orphan after an update.
      xdg.configFile."autostart/orca-ide.desktop".source =
        "${orcaPkg}/share/orca/orca-autostart.desktop";
    })
  ];
}
