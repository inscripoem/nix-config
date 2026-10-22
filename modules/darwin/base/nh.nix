# The real `nh` on darwin, mirroring modules/nixos/base/nh.nix. The locked
# nix-darwin has no programs.nh module, so the CLI and the periodic clean are
# wired by hand: a root launchd daemon stands in for NixOS's root systemd
# service running `nh clean all`.
{ config, pkgs, vars, ... }:

{
  environment.systemPackages = [ pkgs.nh ];
  environment.variables.NH_FLAKE = "/Users/${vars.username}/nix-config";

  # Same retention as NixOS: --keep-since 4d --keep 3, run as root so the
  # darwin system profile and all users' profiles are cleaned, then the store
  # is garbage-collected. nh >= 4.2 also scans macOS XDG profiles for UIDs
  # 501-601, covering the primary user's home-manager generations.
  # Schedule matches nix-darwin's own nix-gc default (Sunday 03:15).
  #
  # NixOS's nh-clean timer is Persistent=true. launchd already reruns calendar
  # jobs missed during sleep on wake; the stamp guard below covers the last
  # gap, a power-off across the scheduled run: RunAtLoad fires at every boot
  # and every darwin-rebuild activation, and the guard makes those cheap
  # no-ops unless the last successful clean is >= 6 days old.
  launchd.daemons.nh-clean = {
    path = [ config.nix.package pkgs.nh ];
    serviceConfig.RunAtLoad = true;
    serviceConfig.StartCalendarInterval = [{
      Weekday = 7;
      Hour = 3;
      Minute = 15;
    }];
    script = ''
      stamp=/var/root/.nh-last-clean
      last=0
      [ -f "$stamp" ] && read -r last < "$stamp"
      if [ $(( $(date +%s) - last )) -lt $((6 * 24 * 3600)) ]; then
        exit 0
      fi
      nh clean all --keep-since 4d --keep 3 && date +%s > "$stamp"
    '';
  };
}
