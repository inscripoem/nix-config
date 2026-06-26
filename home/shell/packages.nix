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
    bottom
    gping
    lazygit
  ];
}
