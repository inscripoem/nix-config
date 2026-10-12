{ vars, ... }:

{
  # Required by nix-darwin for Homebrew activation to run as the account that
  # owns the existing /opt/homebrew installation.
  system.primaryUser = vars.username;

  homebrew = {
    enable = true;

    # Phase 3 adopts the existing inventory without mutating it beyond
    # installing a subsequently declared missing item. Upgrades and strict
    # cleanup remain explicit follow-up decisions.
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };

    taps = [
      {
        name = "anomalyco/tap";
        trusted = true;
      }
    ];

    # Formulae already supplied by Home Manager are intentionally omitted:
    # fastfetch, fd, git, go, neovim, starship, unzip, xz, and zoxide.
    # Keep copies required by Homebrew dependencies, such as xz.
    brews = [
      "bzip2"
      "c-blosc"
      "ffmpeg"
      "gh"
      "git-filter-repo"
      "git-xet"
      "gzip"
      "hdf5"
      "lynx"
      "lz4"
      "lzo"
      "mole"
      "pdm"
      "pipx"
      "pkgconf"
      "poetry"
      "protobuf"
      "smartmontools"
      "anomalyco/tap/opencode"
    ];

    # Exclude apps confirmed absent during migration; see docs/nix-config-orchestration.md.
    # cleanup = "none" leaves undeclared Homebrew installations untouched.
    casks = [
      "1password"
      "appcleaner"
      "blender"
      "claude-code"
      "codex"
      "feishu"
      "font-maple-mono-nf-cn"
      "font-source-sans-3"
      "godot"
      "handbrake-app"
      "heptabase"
      "hiddenbar"
      "iina"
      "iterm2"
      "keka"
      "krita"
      "localsend"
      "maccy"
      "microsoft-auto-update"
      "microsoft-office"
      "notion"
      "obsidian"
      "orbstack"
      "pearcleaner"
      "raycast"
      "stats"
      "steam"
      "steamcmd"
      "tailscale-app"
      "telegram"
      "termius"
      "typora"
      "uninstallpkg"
      "vivaldi"
      "warp"
      "zcode"
      "zoom"
      "zotero"
    ];
  };
}
