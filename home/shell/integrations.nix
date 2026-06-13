{
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };

  programs.eza = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };

  programs.carapace = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
}
