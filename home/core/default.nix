{ config, lib, pkgs, ... }:

{
  imports = [
    ./git.nix
    ./ssh.nix
    ./shell.nix
    ./editors.nix
    ./packages.nix
    ./nix-index.nix
  ];

  home.username = "inscripoem";
  home.homeDirectory = lib.mkDefault (
    "${if pkgs.stdenv.hostPlatform.isDarwin then "/Users" else "/home"}/${config.home.username}"
  );
  home.stateVersion = "25.05";
}
