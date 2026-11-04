{ config, lib, pkgs, deepseek-harness, ... }:

let
  cfg = config.packs.ai;
  dshPkgs = deepseek-harness.packages.${pkgs.stdenv.hostPlatform.system};
  dshLegacyPkgs = deepseek-harness.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  # dsh-desktop-official: DeepSeek Harness desktop app, source-built for
  # Linux by the community deepseek-harness flake (dataelement's own
  # releases ship macOS/Windows only). It bundles the official runtime and
  # Web UI, so version bumps ride flake updates of that input.
  dshUpstream = dshPkgs.dsh-desktop-official;

  # Tray icon for the Linux patch applied in dshPkg below: upstream ships
  # tray.ico for Windows only and no icon at all in the Linux build, so reuse
  # the desktop-entry mark and rasterize it at build time.
  dshTrayIcon = pkgs.runCommand "dsh-tray-icon" {
    nativeBuildInputs = [ pkgs.librsvg ];
  } ''
    rsvg-convert -w 32 -h 32 ${../../../modules/nixos/desktop/icons/dsh.svg} -o $out
  '';

  # Upstream creates its tray — and the one-time first-close notice that
  # points at it — behind `process.platform === "win32"` in
  # resources/app/lib/main.js, so on Linux close means hide with no way back
  # to the window and no exit entry. Electron's StatusNotifierItem path works
  # on Linux (verified against a live DankMaterialShell watcher), so re-enable
  # upstream's own code instead of reimplementing it. The substitutions are
  # anchored: a bundle bump that moves one fails the build rather than
  # silently shipping a tray-less app.
  dshPkg =
    if !cfg.dsh.tray.enable then
      dshUpstream
    else
      dshUpstream.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          main="$out/lib/dsh-desktop/resources/app/lib/main.js"
          substituteInPlace "$main" --replace-fail \
            'if (process.platform === "win32") try {' \
            'if (process.platform === "win32" || process.platform === "linux") try {'
          substituteInPlace "$main" --replace-fail \
            'join(process.resourcesPath, "tray.ico")' \
            'join(process.resourcesPath, process.platform === "linux" ? "tray.png" : "tray.ico")'
          substituteInPlace "$main" --replace-fail \
            'const backgroundNotice = process.platform === "win32" ?' \
            'const backgroundNotice = process.platform === "win32" || process.platform === "linux" ?'
          install -Dm644 ${dshTrayIcon} "$out/lib/dsh-desktop/resources/tray.png"
        '';
      });

  # Bare official dsh CLI (kernel). Kept out of home.packages on purpose:
  # the frozen TUI preset below also ships bin/dsh, and two packages
  # providing bin/dsh collide in the Home Manager profile. The preset is the
  # PATH dsh; this bare CLI is what services.dsh serves the user-state web
  # profile with, so the service closure stays free of the TUI bundle.
  dshCliPkg = dshPkgs.dsh;

  # Frozen TUI composition — kernel and TUI bundle assembled in one hoisted
  # node_modules tree, so the two-copy structure behind the live TUI crash
  # (store kernel + npm TUI copy) is gone by construction. Decision record
  # (2026-11-04): the former npm delegating launcher (dsh-tui-launcher) is
  # removed; the TUI now follows flake updates instead of its own /update.
  # Accepted costs: no claude-agent-sdk peer in the frozen tree, and
  # hand-installed plugins in the managed nix-tui profile are restored by
  # the preset's seed wrapper on every launch — experimental plugins belong
  # to the user-state desktop/web profiles, never to nix-tui.
  dshTuiPkg = dshLegacyPkgs.presets.tui;

  # Orca's dsh contract is hardcoded in its agent table (detectCmd
  # `dsh-tui`, required `dsh`, launchCmd `dsh-tui .`) and a command override
  # only changes the launch line, not detection. This three-line adapter
  # exposes the frozen preset under the name Orca probes and maps
  # `dsh-tui .` to `dsh nix-tui .`; it carries no bootstrap or update logic,
  # so the old launcher's profile layers are not reintroduced.
  dshTuiEntry = pkgs.writeShellScriptBin "dsh-tui" ''
    exec ${dshTuiPkg}/bin/dsh nix-tui "$@"
  '';
in
{
  imports = [ deepseek-harness.homeModules.default ];

  options.packs.ai.dsh = {
    # Opt-in extra: DeepSeek Harness (dsh) desktop app — Electron shell over
    # the official Harness Web UI (tray, notifications, phone pairing, PPT
    # mode). Same "bring your own agent" family as orca/workbuddy above.
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "dsh (DeepSeek Harness) desktop app, opt-in per host";
    };

    # The Linux build of the desktop app hides its window on close and, with
    # no tray, offers no way back to it and no exit entry. dshPkg re-enables
    # upstream's own tray implementation, so this is on by default; turning it
    # off falls back to the unmodified upstream package (a different store
    # path, so it rebuilds).
    tray.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "expose the dsh desktop tray on Linux (DBus StatusNotifierItem)";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.dsh.enable {
      # One TUI copy, store-frozen in the preset (kernel + TUI + headless
      # bundles share one node_modules tree). The preset's managed profile
      # is nix-tui; the old user-state dsh-tui profile is left in place,
      # unused.
      home.packages = [
        dshPkg
        dshTuiPkg
        dshTuiEntry
      ];

      # Local web entry for remote access: a Home Manager user service so
      # DSH_HOME stays ~/.dsh and the existing web profile (including its
      # magpie patch) is served as-is. The NixOS services.dsh module is not
      # used here: it runs from /var/lib/dsh as a DynamicUser with
      # ProtectHome=true, which cannot read ~/.dsh. Bound to loopback;
      # remote exposure rides the CF tunnel (step 2), never openFirewall.
      services.dsh = {
        enable = true;
        package = dshCliPkg;
        profile = "web";
        listenAddress = "127.0.0.1";
        port = 3080;
      };
    })
  ];
}