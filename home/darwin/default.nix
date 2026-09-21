{ config, ... }:

let
  onePasswordAgent = "${config.home.homeDirectory}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
in
{
  imports = [ ../core.nix ];

  # The system layer owns Lix; HM must not manage a second Nix configuration.
  nix.enable = false;

  # Fish enables mandb indexing by default, but its current manuals fail
  # whatis parsing. Keep manual pages without generating that index on Mac.
  programs.man.generateCaches = false;

  # Reuse the native app; do not install another 1Password GUI through Nix.
  programs.git.settings.gpg.ssh.program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
  programs.ssh.settings."*".IdentityAgent = ''"${onePasswordAgent}"'';
  home.sessionVariables.SSH_AUTH_SOCK = onePasswordAgent;

  # Git reads both paths. Manage the existing macOS target so a legacy
  # ~/.gitconfig cannot silently override the generated XDG configuration.
  xdg.configFile."git/config".enable = false;
  home.file.".gitconfig".source = config.xdg.configFile."git/config".source;
}
