{ config, lib, pkgs, vars, nix-index-database, ... }:

{
  imports = [
    ./git.nix
    ./ssh.nix
    ./shell.nix
    ./editors.nix
    ./packages.nix
    ./nix-index.nix
    # Prebuilt nix-index database + comma wiring (all platforms). HM
    # receives flake inputs as extraSpecialArgs (lib/{nixos,darwin}Modules.nix).
    nix-index-database.homeModules.nix-index
  ];

  home.username = vars.username;
  home.homeDirectory = lib.mkDefault (
    "${if pkgs.stdenv.hostPlatform.isDarwin then "/Users" else "/home"}/${config.home.username}"
  );
  # NixOS and HM stateVersions intentionally follow the same value.
  home.stateVersion = vars.stateVersion;
}
