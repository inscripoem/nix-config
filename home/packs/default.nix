{
  # Shared secret-service backend name for Electron/Chromium apps.
  # Electron's keytar/os_crypt checks XDG_CURRENT_DESKTOP to decide whether
  # to initialize a keyring backend — unknown DEs (e.g. "niri") get skipped
  # entirely, regardless of whether org.freedesktop.secrets is available on
  # DBus. Passing --password-store=<backend> bypasses that detection and
  # calls libsecret directly. Consumed by desktop/browsers.nix,
  # desktop/editors-gui.nix, and packs/ai/workbuddy.nix.
  # System-level keyring infrastructure: modules/nixos/desktop/keyring.nix.
  # Defined here rather than in the desktop group: packs are imported
  # centrally into every NixOS host's HM via sharedModules in
  # lib/nixosModules.nix, so any host enabling a pack that consumes this
  # module arg resolves it — defining it only in the desktop group would
  # fail with an attribute-missing error on non-desktop hosts.
  _module.args.passwordStore = "gnome-libsecret";

  imports = [
    ./ai
    ./creative.nix
    ./gaming.nix
    ./office.nix
    ./onedrive.nix
    ./toolchain.nix
  ];
}
