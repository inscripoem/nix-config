{ ... }:

let
  onePasswordAgent = "~/.1password/agent.sock";
in
{
  programs.ssh = {
    enable = true;

    # Opt out of home-manager's legacy "set every common ssh_config knob
    # to its OpenSSH default value" behaviour. That block is on its way
    # to deprecation (release-notes; eval emits a warning otherwise) and
    # every value it would set matches what `ssh` already does without
    # being told, so dropping it changes nothing functionally and just
    # quiets the warning. If we ever want non-default behaviour for one
    # of those knobs (controlMaster, serverAliveInterval, ...), add it
    # explicitly to settings."*" below.
    enableDefaultConfig = false;

    settings = {
      # All hosts route through the 1Password SSH agent. See
      # docs/ssh-agent.md §2 / §3 for why this lives in $SSH_AUTH_SOCK
      # AND in IdentityAgent simultaneously. The agent itself, its key
      # allowlist (agent.toml), and the $SSH_AUTH_SOCK export are
      # configured in home/secrets/1password.nix.
      "*" = {
        IdentityAgent = onePasswordAgent;
      };

      # github.com over port 443: the SSH-over-HTTPS endpoint, used to
      # tunnel out of networks that drop outbound 22.
      "github.com" = {
        HostName = "ssh.github.com";
        Port = 443;
        User = "git";
      };
    };
  };
}
