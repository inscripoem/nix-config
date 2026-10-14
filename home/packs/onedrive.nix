{ config, lib, pkgs, ... }:
let
  cfg = config.packs.onedrive;
in {
  options.packs.onedrive.enable =
    lib.mkEnableOption "OneDrive sync client (abraunegg) with a monitor-mode user service";

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      home.packages = [ pkgs.onedrive ];

      # Client config (~/.config/onedrive/config). Options left unset fall
      # back to the client's internal defaults (upstream syntax: quoted
      # strings, one key per line). First run: `onedrive --sync` authorises
      # via the desktop browser and performs the initial download. Changing
      # skip_dir/skip_file after that requires `onedrive --sync --resync`.
      xdg.configFile."onedrive/config".text = ''
        sync_dir = "~/OneDrive"

        # Bare names match directories of that name at any depth (upstream
        # default, skip_dir_strict_match=false). Keeps regenerable trees and
        # .git churn out of the sync scope; extend with explicit relative
        # paths (from sync_dir) when needed.
        skip_dir = "node_modules|target|dist|.git|.venv|__pycache__|.cache"

        # Must include every entry of the client's built-in default
        # ("~*|.~*|*.tmp|*.swp|*.partial" in 2.5.11): the client warns about
        # missing defaults when skip_file is overridden. .swo covers the
        # other vim swap file.
        skip_file = "~*|.~*|*.tmp|*.swp|*.partial|*.swo"
      '';
    })

    # Monitor-mode daemon. The resident process is the point of this pack —
    # a stopped sync client protects nothing — so unlike on-demand app
    # services this one is enabled unconditionally once the pack is on.
    # Upstream unit conventions: restart on failure only, never on exit 78
    # (EX_CONFIG: a --resync the operator must run by hand), and no start
    # rate limit so the pre-authorisation retry loop outlives systemd's
    # default burst limit until the first `onedrive --sync` completes.
    (lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isLinux) {
      systemd.user.services.onedrive = {
        Unit = {
          Description = "OneDrive sync client (monitor mode)";
          Documentation = [ "https://github.com/abraunegg/onedrive" ];
          # network-online.target is a system target; a user unit can only
          # meaningfully order after default.target. The client retries
          # connectivity with its own backoff.
          After = [ "default.target" ];
          StartLimitIntervalSec = 0;
        };
        Service = {
          ExecStart = "${pkgs.onedrive}/bin/onedrive --monitor";
          Restart = "on-failure";
          RestartSec = 15;
          RestartPreventExitStatus = 78;
        };
        Install.WantedBy = [ "default.target" ];
      };
    })
  ];
}
