{ config, lib, ... }:

{
  imports = [
    ../darwin
    ../packs/toolchain.nix
  ];

  packs.toolchain.enable = true;

  # Local utilities remain user-owned; shell initialization lives in home/core.
  home.sessionPath = [
    "${config.home.homeDirectory}/.claude/bin"
    "${config.home.homeDirectory}/.tools"
  ];

  programs.git = {
    lfs.enable = true;
    settings = {
      user.name = "CHANG Xuben";
      init.defaultBranch = "main";
      lfs."customtransfer.xet" = {
        path = "git-xet";
        args = "transfer";
        concurrent = true;
      };
    };
  };

  # OrbStack owns its generated file; private hosts stay outside the flake.
  programs.ssh.includes = [
    "~/.orbstack/ssh/config"
    "~/.ssh/config.local"
  ];

  home.activation.checkAirMigrationInputs = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    if [[ ! -f "$HOME/.ssh/config.local" || ! -r "$HOME/.ssh/config.local" ||
          -L "$HOME/.ssh/config.local" || ! -O "$HOME/.ssh/config.local" ]]; then
      echo "air: restore ~/.ssh/config.local from a private backup as a readable, user-owned regular file before switching" >&2
      exit 1
    fi
    if [[ -L "$HOME/.config/nvim" ]]; then
      echo "air: back up the ~/.config/nvim symlink itself before switching; do not modify its SpaceVim target" >&2
      exit 1
    fi
    if [[ -e "$HOME/.config/nvim/init.vim" || -L "$HOME/.config/nvim/init.vim" ]]; then
      echo "air: preserve the legacy init.vim before switching; it conflicts with HM's init.lua" >&2
      exit 1
    fi
  '';

  # Keep on-use cache updates, without adding a tldr-update LaunchAgent.
  programs.tealdeer.enableAutoUpdates = false;
}
