{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    maple-mono.NF-CN
    net-tools
  ];
  environment.variables.EDITOR = "vim";
}
