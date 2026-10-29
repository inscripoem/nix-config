{ config, lib, pkgs, llm-agents, ... }:

let
  cfg = config.packs.ai;
  agentPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # The desktop app keeps its binary but the terminal `zcode` name moves to
  # pkgs.zcode-cli (official open-source CLI, built from source): the
  # desktop-bundled glm/zcode.cjs cannot run its TUI upstream — the
  # distribution does not ship @zcode/tui. The GUI launcher becomes
  # `zcode-desktop`, keeping the original wrapper's xdg/ozone/IME flags,
  # and the shipped zcode.desktop Exec is repointed at it because it
  # hardcodes `zcode`. Paths assume the Linux deb layout; only Linux hosts
  # enable packs.ai.zcode (air does not). Update tracks are decoupled:
  # desktop via the llm-agents input, CLI via update-versions.sh.
  zcodePkg = pkgs.symlinkJoin {
    # Version from the upstream package keeps the generation diff readable:
    # llm-agents updates render as a plain old -> new version line. (The
    # old "stable name" rule predates nh's dix diff, whose name splitter
    # handles custom pname-version names correctly.)
    pname = "zcode-desktop-joined";
    version = agentPkgs.zcode.version;
    paths = [ agentPkgs.zcode ];
    postBuild = ''
      mv $out/bin/zcode $out/bin/zcode-desktop
      rm $out/share/applications/zcode.desktop
      sed 's|^Exec=zcode|Exec=zcode-desktop|' \
        ${agentPkgs.zcode}/share/applications/zcode.desktop \
        > $out/share/applications/zcode.desktop
    '';
  };
in
{
  options.packs.ai.zcode = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "zcode CLI";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.zcode.enable {
      home.packages = [
        zcodePkg
        pkgs.zcode-cli
      ];

      # ZCode is an Electron app that calls setAsDefaultProtocolClient() on
      # every launch, rewriting a user-level desktop file into
      # ~/.local/share/applications/zcode.desktop. That copy shadows the one
      # shipped by the package and breaks xdg-desktop-portal's registration of
      # x-scheme-handler/zcode — after the browser OAuth redirect the portal
      # then shows an empty "Open With" dialog ("no available apps"). Register
      # the scheme via [Added Associations]: GLib only enumerates schemes
      # listed there, and this tweak path is immune to the desktop-file
      # shadowing.
      xdg.dataFile."applications/mimeapps.list".text = ''
        [Added Associations]
        x-scheme-handler/zcode=zcode.desktop;
      '';
    })
  ];
}
