{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    maple-mono.NF-CN
    net-tools
    python3
  ];
  environment.variables.EDITOR = "vim";
}
