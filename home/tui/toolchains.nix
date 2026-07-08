{ pkgs, ... }:
{
  home.packages = [
    pkgs.devenv
    pkgs.tokei
    pkgs.bun
    pkgs.nodejs_22
    pkgs.pnpm
    pkgs.yarn
    pkgs.uv
    pkgs.rustup
  ];
}
