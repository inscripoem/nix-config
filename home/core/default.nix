{ pkgs, ... }:

{
  imports = [
    ./git.nix
    ./ssh.nix
  ];

  home.username = "inscripoem";
  home.homeDirectory = "/home/inscripoem";

  home.stateVersion = "25.05";

  programs.nix-index = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };

  home.packages = with pkgs; [
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
