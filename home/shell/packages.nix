{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ripgrep
    fd
    jq
    yq-go
    duf
    dust
    htop
    glances
    bottom
    gping
    lazygit
  ];
}
