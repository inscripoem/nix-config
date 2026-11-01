{ config, lib, pkgs, passwordStore, ... }:

let
  cfg = config.packs.ai;

  # The overridden derivation must be the ONLY workbuddy in the module: the
  # menu entry (home.packages) references it, so the launched app carries the
  # --password-store wrapper. Referencing the base pkgs.workbuddy anywhere
  # would pull a second, flag-less copy into the closure.
  workbuddyPkg = pkgs.workbuddy.override {
    commandLineArgs = "--password-store=${passwordStore}";
  };
in
{
  options.packs.ai.workbuddy = {
    # Opt-in extra: Tencent CodeBuddy team's agentic desktop workspace.
    # Single Linux build (no CN/international split on Linux); the same
    # package serves both account regions.
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "workbuddy agentic desktop app (Tencent), opt-in per host";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.workbuddy.enable {
      home.packages = [ workbuddyPkg ];
      # No XDG autostart entry (removed 2026-11-01). Do NOT enable the app's
      # own "auto launch" toggle instead: setLoginItemSettings bakes the
      # current store path into ~/.config/autostart, which breaks after a
      # GC, or falls back to the raw Electron binary (no sandbox flags, no
      # bwrap/socat on PATH).

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
  ];
}
