{ pkgs, ... }:

let
  signingKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyJUP8n6z8K95LFwLPZQ9jE4k+WmIzocTXkXvAUhRJG";
  allowedSigners = pkgs.writeText "git-allowed-signers" ''
    changxuben@gmail.com ${signingKey}
  '';
in
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
        signingkey = "key::${signingKey}";
      };
      gpg.format = "ssh";
      gpg.ssh.allowedSignersFile = toString allowedSigners;
      commit.gpgsign = true;
      tag.gpgsign = true;
    };
  };

  programs.nix-index = {
    enable = true;
    enableFishIntegration = true;
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
    
    # Vibe Coding
    gemini-cli
  ];
}
