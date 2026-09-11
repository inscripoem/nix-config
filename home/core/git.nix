{ pkgs, lib, ... }:

let
  signingKey = builtins.readFile ../../keys/ssh-ed25519.pub;
  allowedSigners = pkgs.writeText "git-allowed-signers" ''
    changxuben@gmail.com ${signingKey}
  '';
in
{
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = lib.mkDefault "inscripoem";
        email = "changxuben@gmail.com";
        signingkey = "key::${signingKey}";
      };
      gpg.format = "ssh";
      gpg.ssh.allowedSignersFile = toString allowedSigners;
      # Sign commits/tags directly via 1Password's `op-ssh-sign` helper
      # instead of going through ssh-agent. Faster (no agent round-trip),
      # and -- crucially -- it asks 1Password for the key by its public
      # half (`user.signingkey` above), so it works even if the agent
      # somehow forgets the key, $SSH_AUTH_SOCK is unset, or
      # `~/.config/1Password/ssh/agent.toml` excludes the signing vault.
      # See docs/ssh-agent.md §6.
      gpg.ssh.program = lib.mkDefault (lib.getExe' pkgs._1password-gui "op-ssh-sign");
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
