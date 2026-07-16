# Force Electron-based apps to use gnome-keyring via libsecret instead of DE
# auto-detection. Electron's keytar/os_crypt checks XDG_CURRENT_DESKTOP to decide
# whether to initialize a keyring backend — unknown DEs (e.g. "niri") get skipped
# entirely, regardless of whether org.freedesktop.secrets is available on DBus.
#
# --password-store=gnome-libsecret bypasses this detection and calls libsecret
# directly. This works across any DE/compositor.
#
# System-level keyring infrastructure: modules/nixos/desktop/keyring.nix
{ pkgs, ... }: {
  home.packages = [
    # Vivaldi (multimedia codecs also needed here since override is one-shot)
    (pkgs.vivaldi.override {
      commandLineArgs = "--password-store=gnome-libsecret";
      proprietaryCodecs = true;
    })
  ];

  # VSCode
  programs.vscode.package = pkgs.vscode.override {
    commandLineArgs = "--password-store=gnome-libsecret";
  };
}