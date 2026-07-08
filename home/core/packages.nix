{ pkgs, ... }:

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
    lazygit
    fastfetch
    zip
    xz
    unzip
    p7zip

    # nix related
    nix-output-monitor

    # system tools
    sysstat
    lm_sensors
    ethtool
    pciutils
    usbutils
  ];
}
