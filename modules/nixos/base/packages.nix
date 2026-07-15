{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    maple-mono.NF-CN
    gh
  ];
  environment.variables.EDITOR = "vim";
}
