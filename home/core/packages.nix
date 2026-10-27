{ pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    # CLI utilities
    ripgrep
    fd
    jq
    yq-go
    duf
    dust
    htop
    bottom
    gping
    mosh
    lazygit
    fastfetch
    zip
    xz
    unzip
    p7zip

    # nix related
    nix-output-monitor
  ] ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    # Linux system tools
    sysstat
    lm_sensors
    ethtool
    pciutils
    usbutils

    # Run downloaded .AppImage files without packaging them first
    appimage-run
  ];
}
