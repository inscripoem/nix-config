{
  # Shared secret-service backend name for Electron/Chromium apps in this
  # desktop group. Electron's keytar/os_crypt checks XDG_CURRENT_DESKTOP to
  # decide whether to initialize a keyring backend — unknown DEs (e.g. "niri")
  # get skipped entirely, regardless of whether org.freedesktop.secrets is
  # available on DBus. Passing --password-store=<backend> bypasses that
  # detection and calls libsecret directly. Consumed by browsers.nix,
  # editors-gui.nix, and pkgs/trae-cn.nix override sites.
  # System-level keyring infrastructure: modules/nixos/desktop/keyring.nix
  _module.args.passwordStore = "gnome-libsecret";

  imports = [
    ./terminals.nix
    ./desktop-env.nix
    ./editors-gui.nix
    ./emacs.nix
    ./browsers.nix
    ./media.nix
    ./productivity.nix
    ./social.nix
    ./1password.nix
    ./glances.nix
    ./cc-switch.nix
    ./rime.nix
    ./fcitx5.nix
    ./niri.nix
  ];
}