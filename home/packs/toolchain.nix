{ pkgs, ... }:
{
  home.packages = [
    pkgs.bun
    pkgs.nodejs_22
    pkgs.pnpm
    pkgs.yarn
    pkgs.uv
    pkgs.rustup
    pkgs.just
    pkgs.devenv
  ];
}
