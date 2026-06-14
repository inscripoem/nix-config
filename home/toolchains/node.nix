{ pkgs, ... }:

{
  home.packages = [
    pkgs.bun
    pkgs.nodejs_22
    pkgs.pnpm
    pkgs.yarn
  ];
}
