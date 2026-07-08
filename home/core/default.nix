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
  home.homeDirectory = "/home/inscripoem";
  home.stateVersion = "25.05";
}
