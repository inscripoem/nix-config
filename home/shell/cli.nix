{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ripgrep 
    jq 
    yq-go 
    eza 
    fzf 
  ];
}
