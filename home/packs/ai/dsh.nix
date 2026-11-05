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

  # Profile seed YAML: nixpkgs writers.writeYAML emits a "%YAML 1.1"
  # directive. pnpm 11 rejects that header in pnpm-workspace.yaml with
  # ERR_PNPM_INVALID_WORKSPACE_CONFIGURATION, even though the package
  # install itself succeeds. The seed generator uses writers.writeYAML for
  # every profile YAML; strip the directive only from the workspace file,
  # leaving cordis.patch.yml and home patches on the original writer.
  dshWriters = pkgs.writers // {
    writeYAML = name: value:
      if name == "dsh-profile-pnpm-workspace.yaml" then
        pkgs.runCommand name { nativeBuildInputs = [ pkgs.gnused ]; } ''
          cp ${pkgs.writers.writeYAML name value} $out
          sed -i '/^%YAML /d' $out
          sed -i '1{/^---$/d}' $out
        ''
      else
        pkgs.writers.writeYAML name value;
  };

  # Base dsh package for both the web service and the TUI preset. The
  # workspace-writer fix must be part of the package that generates the
  # profile templates; an explicit services.dsh.package would bypass it.
  dshBase = dshPkgs.dsh.override { writers = dshWriters; };

  # Bare dsh CLI (kernel), with the profile-workspace writer fix. Kept out
  # of home.packages on purpose: the frozen TUI preset below also ships
  # bin/dsh, and two packages providing bin/dsh collide in the Home Manager
  # profile. The preset is the PATH dsh; this bare CLI is what services.dsh
  # serves the user-state web profile with, so the service closure stays
  # free of the TUI bundle.
  dshCliPkg = dshBase;

  # Frozen TUI composition — kernel and TUI bundle assembled in one hoisted
  # node_modules tree, so the two-copy structure behind the live TUI crash
  # (store kernel + npm TUI copy) is gone by construction. Decision record
  # (2026-11-04): the former npm delegating launcher (dsh-tui-launcher) is
  # removed; the TUI now follows flake updates instead of its own /update.
  # Accepted costs: no claude-agent-sdk peer in the frozen tree, and
  # hand-installed plugins in the managed nix-tui profile are restored by
  # the preset's seed wrapper on every launch — experimental plugins belong
  # to the user-state desktop/web profiles, never to nix-tui.
  #
  # Orca's global hook patch inserts @deepseek-ai/dsh-hooks-claude-code into
  # every profile; the managed nix-tui profile has no profile-level
  # node_modules, so the bridge is added to the preset's composed tree via a
  # minimal bundle instead of a hand-installed profile plugin.
  dshScope = pkgs.extend deepseek-harness.overlays.default;
  dshOrcaHooksBundle = dshScope.dsh.callPackage ../../../pkgs/dsh-orca-hooks.nix { };
  dshTuiPkg = dshBase.override {
    writers = dshWriters;
    pname = "dsh-tui";
    defaultBundles = [ dshLegacyPkgs.bundles.headless ];
    defaultProfile = "nix-tui";
    profiles = {
      tui = {
        requiresTui = true;
        bundles = [ dshOrcaHooksBundle ];
        # Magpie manages this profile's model providers and edits it at
        # runtime. Managed mode would restore the declared patch on every
        # launch, so the TUI profile is mutable: Nix seeds it once, then
        # Magpie's edits persist. Provider/model settings are user state
        # under ~/.dsh/profiles/nix-tui; back that directory up before
        # reseeding. The cost is that later preset changes no longer
        # auto-apply; re-seed by removing the profile.
        mode = "mutable";
      };
    };
  };

  # Orca's dsh contract is hardcoded in its agent table (detectCmd
  # `dsh-tui`, required `dsh`, launchCmd `dsh-tui .`) and a command override
  # only changes the launch line, not detection. This adapter exposes the
  # frozen preset under the name Orca probes and maps `dsh-tui` to
  # `dsh nix-tui`. The trailing "." is Orca's workspace marker from the old
  # npm launcher; the preset's TUI treats a positional "." as the initial
  # prompt, so it is dropped here — Orca already sets the terminal cwd and
  # injects the real task over stdin after startup. No bootstrap or update
  # logic is reintroduced.
  dshTuiEntry = pkgs.writeShellScriptBin "dsh-tui" ''
    args=()
    for arg in "$@"; do
      [ "$arg" = "." ] || args+=("$arg")
    done
    exec ${dshTuiPkg}/bin/dsh nix-tui "''${args[@]}"
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

      # Composed web service package: services.dsh.package defaults to a
      # package composed from this bare kernel plus the declared profiles.
      # Setting services.dsh.package explicitly would bypass that
      # composition and serve the bare CLI without the profile bundles.
      programs.dsh.package = dshCliPkg;

      # Local web entry: a Home Manager user service so DSH_HOME stays
      # ~/.dsh. The served profile is the mutable nix-web skeleton below;
      # its provider settings and dshmarket installs live under
      # ~/.dsh/profiles/nix-web, outside git. The old user-state web profile
      # is left untouched for rollback. The NixOS services.dsh module is not
      # used here: it runs from /var/lib/dsh as a DynamicUser with
      # ProtectHome=true, which cannot read ~/.dsh. Bound to loopback;
      # remote access stays off until an ingress/auth decision is made.
      services.dsh = {
        enable = true;
        profile = "nix-web";
        profiles.web = {
          # Every compatible bundle that desktop and the flake both ship
          # under the same package (11 declared; base is added by the
          # module, making 12 same-package entries, and the bare dsh
          # default adds headless). The flake's billion-context 0.2.27
          # requires dsh <0.2.1 and is skipped by the rc.3 kernel, so the
          # desktop-compatible 0.1.208 is installed as user state instead.
          # The flake's experimental market bundle is intentionally absent:
          # upstream ships an empty index client, while the desktop uses
          # dshmarket's community catalog. dshmarket is installed as user
          # state after the first seed. Orca's hook bundle is absent too:
          # this profile is never launched by Orca, and the hook warning
          # is harmless.
          #
          # Mutable: Nix seeds the profile once; runtime provider settings
          # and plugin installs persist. Later bundle-list changes require
          # backing up and removing ~/.dsh/profiles/nix-web.
          bundles = [
            dshLegacyPkgs.bundles.web-app
            dshLegacyPkgs.bundles.experimental-auto-review
            dshLegacyPkgs.bundles.experimental-agent-team-profile
            dshLegacyPkgs.bundles.experimental-tool-worktree
            dshLegacyPkgs.bundles.experimental-terminal-bundle
            dshLegacyPkgs.bundles.experimental-session-search
            dshLegacyPkgs.bundles.experimental-session-titles-bundle
            dshLegacyPkgs.bundles.experimental-ralph-bundle
            dshLegacyPkgs.bundles.subagent-codex
            dshLegacyPkgs.bundles.better-sidebar
            dshLegacyPkgs.bundles.context
          ];
          mode = "mutable";
        };
        listenAddress = "127.0.0.1";
        port = 3080;
      };
    })
  ];
}