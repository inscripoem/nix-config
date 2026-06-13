{ pkgs, ... }:

let
  signingKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyJUP8n6z8K95LFwLPZQ9jE4k+WmIzocTXkXvAUhRJG";
  allowedSigners = pkgs.writeText "git-allowed-signers" ''
    changxuben@gmail.com ${signingKey}
  '';
in
{
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "inscripoem";
        email = "changxuben@gmail.com";
        signingkey = "key::${signingKey}";
      };
      gpg.format = "ssh";
      gpg.ssh.allowedSignersFile = toString allowedSigners;
      commit.gpgsign = true;
      tag.gpgsign = true;
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
      side-by-side = false;
      syntax-theme = "Catppuccin Macchiato";
    };
  };
}
