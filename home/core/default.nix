{ pkgs, ... }:

{
  home.username = "inscripoem";
  home.homeDirectory = "/home/inscripoem";

  home.stateVersion = "25.05";

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "inscripoem";
        email = "changxuben@gmail.com";
      };
    };
  };

  programs.nix-index = {
    enable = true;
    enableFishIntegration = true;
  };

  home.packages = with pkgs; [
    neofetch
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
    
    # Vibe Coding
    gemini-cli
  ];
}
