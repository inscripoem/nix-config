{
  lib,
  pkgs,
  config,
  ...
}:

let
  # User content roots handed to dsearch (daemon: modules/nixos/desktop/
  # dms-shell.nix). SiYuan and Games are deliberately not indexed: notebook
  # block files carry hash filenames with no lookup value, and a wine
  # prefix's dosdevices/z: -> / symlink would spend the depth budget on /.
  dsearchRoots = [
    "Desktop"
    "Documents"
    "Downloads"
    "Music"
    "Pictures"
    "Public"
    "Templates"
    "Videos"
    "Projects"
    "OneDrive"
    "dev"
    "LocalDev"
    "nix-config"
  ];

  # dsearch 1.6.0 does not apply its built-in exclude list to user-declared
  # index_paths (node_modules ends up fully indexed; verified via
  # `dsearch index check`), so code-dir noise is excluded explicitly here.
  dsearchExcludes = [
    "node_modules"
    "target"
    "vendor"
    "__pycache__"
    "venv"
    ".venv"
    "dist"
    "build"
    "result"
    "deps"
    "_build"
  ];
in
{
  targets.genericLinux.nixGL.vulkan.enable = true;

  programs.plasma = {
    enable = true;
    hotkeys.commands."launch-wezterm" = {
      name = "Launch Wezterm";
      key = "Ctrl+Alt+T";
      command = "wezterm";
    };
    configFile."kwinrc"."Wayland"."VirtualKeyboard" = "org.fcitx.Fcitx5";
    # Let gnome-keyring own org.freedesktop.secrets; KWallet stays
    # only for KDE-internal features (NetworkManager, KMail, etc.)
    configFile."kwalletrc"."org.freedesktop.secrets"."apiEnabled" = false;
  };

  home.packages = with pkgs; [
    deskflow
    wl-clipboard
  ];

  xdg.configFile."autostart/nm-applet.desktop".text = ''
    [Desktop Entry]
    Hidden=true
  '';

  xdg.configFile."autostart/org.deskflow.deskflow.desktop".source =
    "${pkgs.deskflow}/share/applications/org.deskflow.deskflow.desktop";

  # dsearch (DankSearch) index scope for DMS Spotlight's file provider.
  # Docs: https://danklinux.com/docs/danksearch/configuration
  # The built-in excludes (hidden entries, .git, node_modules, target, ...)
  # stay active; max_depth must remain finite: upstream #29 — symlink
  # cycles plus an unlimited depth leave indexing running forever.
  xdg.configFile."danksearch/config.toml".text =
    ''
      # Indexed roots for dsearch. Keep max_depth finite (see upstream #29).
    ''
    + lib.concatMapStrings (root: ''
      [[index_paths]]
      path = "${config.home.homeDirectory}/${root}"
      max_depth = 10
      exclude_dirs = [${lib.concatStringsSep ", " (map (e: ''"${e}"'') dsearchExcludes)}]
      merge_default_exclude_dirs = true

    '') dsearchRoots;
}
