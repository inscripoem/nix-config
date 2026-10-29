{ config, lib, pkgs, deepseek-harness, ... }:

let
  cfg = config.packs.ai;

  # dsh-desktop-official: DeepSeek Harness desktop app, source-built for
  # Linux by the community deepseek-harness flake (dataelement's own
  # releases ship macOS/Windows only). It bundles the official runtime and
  # Web UI, so version bumps ride flake updates of that input.
  dshUpstream = deepseek-harness.packages.${pkgs.stdenv.hostPlatform.system}.dsh-desktop-official;

  # Tray icon for the Linux patch applied in dshPkg below: upstream ships
  # tray.ico for Windows only and no icon at all in the Linux build, so reuse
  # the mark the launcher already uses and rasterize it at build time.
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

  # Bare official dsh CLI (kernel) from the same deepseek-harness flake,
  # version-matched with the desktop app's bundled runtime. Plain official
  # semantics: `dsh <name>` boots profile <name> under $DSH_HOME/profiles
  # (dsh web / dsh headless / dsh tui / dsh plugin, no default-profile
  # injection). It is also what the dsh-tui launcher bootstraps through
  # (`dsh plugin --profile dsh-tui add ...`) and what orca's dsh agent
  # requires on PATH (detectRequiredCommands).
  dshCliPkg = deepseek-harness.packages.${pkgs.stdenv.hostPlatform.system}.dsh;

  # Official @deepseek-harness-tui/dsh-tui launcher — orca's recognized
  # interactive interface for agent kind "dsh" (detectCmd `dsh-tui`,
  # launchCmd `dsh-tui .`, so no per-agent command override). The nix
  # package carries only the zero-dependency thin shell; the full TUI is
  # bootstrapped into ~/.dsh/profiles/dsh-tui on first run through the
  # kernel above and then updates itself in place via the TUI's own
  # /update — this pin gates fresh bootstraps only. The pin must be a
  # version whose declared @deepseek-ai/* requirements accept the kernel
  # above: the flake's own bundle pairing does not extend to npm (e.g.
  # 0.15.0 targets kernel 0.2.0-rc.2 and dsh plugin add rejects it on
  # 0.2.1-rc.2). Update track: update-versions.sh, which resolves the
  # kernel from flake.lock and picks the newest release accepting it. The
  # updater also realigns this rolling profile's @deepseek-ai/* family to
  # the kernel (and the TUI copy to the pin) once the running system is on
  # the target kernel — guarded, because `dsh plugin add` checks its peer
  # contract against the running kernel; before an nhs it only prints the
  # commands. Third-party profile plugins and the Electron-managed desktop
  # profile stay user-state and are never touched by it.
  dshTuiLauncherPkg = pkgs.dsh-tui-launcher;
in
{
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
      # dsh-desktop (Electron shell), the bare kernel CLI, and the official
      # dsh-tui launcher — one TUI copy, self-managed in the launcher's
      # profile. Decision record (2026-10-18): presets.tui (the nix-managed
      # nix-tui profile) was dropped because orca's dsh contract is shaped
      # around the official launcher (detectCmd `dsh-tui`, launchCmd
      # `dsh-tui .`, npm-package realpath), which presets could only serve
      # through a manual per-agent override — and keeping both meant two
      # TUI copies on diverging update tracks. Accepted cost: the TUI is
      # no longer store-frozen — no generation rollback for it, and updates
      # ride its explicit /update from npm; the nix pin gates fresh
      # bootstraps only. presets.tui is one line away if the frozen route
      # is ever wanted back; the two coexist conflict-free.
      home.packages = [
        dshPkg
        dshCliPkg
        dshTuiLauncherPkg
      ];
    })
  ];
}
