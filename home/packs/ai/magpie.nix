{ config, lib, pkgs, ... }:

let
  cfg = config.packs.ai;
in
{
  options.packs.ai.magpie = {
    # Opt-in extra: magpie — provider/model switcher for every agent via a
    # local translating gateway on 127.0.0.1:3425. Self-packaged from
    # upstream release binaries; update track is update-versions.sh. It and
    # cc-switch below both rewrite the agent config files they manage
    # (~/.claude/settings.json, ~/.codex/config.toml) — let only one of them
    # switch providers on a given host, or the last writer wins.
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "magpie agent-model switcher, opt-in per host";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.magpie.enable && pkgs.stdenv.hostPlatform.isLinux) {
      home.packages = [ pkgs.magpie ];

      # XDG autostart of `magpie tray` — the windowless app process that
      # hosts the translating gateway on 127.0.0.1:3425; the window only
      # opens on demand from that same instance. Verified 2026-10-27: any
      # later `magpie` launch probes the gateway first and defers (exit 0,
      # no second process), so tray-at-login never races the GUI and two
      # gateways cannot coexist. A headless `magpie serve` unit was rejected
      # for exactly that reason: with serve holding 3425 the launcher's
      # launch defers and exits, leaving no app instance to open a window.
      # Do NOT reach for `magpie autostart on` / `magpie daemon install`
      # either: both write ~/.config or a unit imperatively and bake the
      # then-current store path into Exec (same failure mode as workbuddy's
      # setLoginItemSettings below). Tray registration ordering after DMS
      # comes free from the global app-@autostart drop-in in
      # home/desktop/niri/default.nix.
      xdg.configFile."autostart/magpie-tray.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=magpie tray
        Exec=${pkgs.magpie}/bin/magpie tray
        Icon=magpie
        Terminal=false
      '';

      # magpie self-registers its magpie:// scheme by rewriting
      # ~/.local/share/applications/magpie.desktop on every fresh launch,
      # exec'ing its own raw ELF path; that user-dir copy shadows the package
      # entry, and the DMS launcher reads user-dir first. Take the file over
      # declaratively so every switch refreshes the store path, and let
      # magpie's rewrites lose: a plain write through the HM symlink hits the
      # read-only store, and a rename-style atomic write only replaces the
      # symlink with a bare-Exec copy — harmless since the ELF carries
      # RUNPATH and is bare-executable (see pkgs/magpie.nix).
      xdg.dataFile."applications/magpie.desktop" = {
        source = "${pkgs.magpie}/share/applications/magpie.desktop";
        force = true;
      };
    })
  ];
}
