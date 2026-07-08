# Home-side 1Password wiring (everything that lives under $HOME).
#
# System-side counterpart (`programs._1password{,-gui}`, browser
# allowlist) is in `system/1password.nix`; the two together
# form a complete 1Password integration.
#
# Three things happen here, all conceptually "tell the rest of the user
# session that the SSH agent is the 1Password one":
#
#   1. $SSH_AUTH_SOCK -> ~/.1password/agent.sock
#      Catches non-OpenSSH consumers (ssh-add, rsync, IDE Git
#      integrations, anything calling libssh* through env discovery).
#
#   2. Mask gcr-ssh-agent.{socket,service}
#      Otherwise gnome-keyring's SSH bridge races for the same role,
#      ends up squatting on /run/user/<uid>/keyring/ssh, and silently
#      shadows the 1Password agent for some tools.
#
#   3. ~/.config/1Password/ssh/agent.toml
#      1Password's allowlist of which vault items count as SSH keys.
#      Without it the agent defaults to vault = "Employee"; on this
#      account the actual keys live in vault = "加密密钥", so the
#      defaults give an empty `ssh-add -l`.
#
# Full design rationale, layer model, recovery procedures: see
# docs/ssh-agent.md.

{ pkgs, ... }:

{
  # See item (1) above.
  home.sessionVariables = {
    SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
  };

  # See item (2) above. An empty unit file under ~/.config/systemd/user/
  # is interpreted by systemd as a masked unit -- it wins over the
  # /etc/systemd/user/ copy installed by services.gnome.gnome-keyring.
  # We keep gnome-keyring itself enabled because it still serves the
  # Secret Service (org.freedesktop.secrets) API for libsecret apps;
  # only its SSH-agent personality is unwanted. See docs/ssh-agent.md
  # §3 for why XDG autostart shadowing does NOT work on gcr >= 4.
  #
  # See item (3) above. Scope = whole vault, not single item: any new
  # key dropped into "加密密钥" via the 1P GUI works without a `nhs`.
  # 1Password offers them in vault insertion order; if we ever hit
  # MaxAuthTries=6 against some server, promote specific items above
  # the vault entry here.
  #
  # The autostart entry starts the 1Password GUI at graphical session
  # login, minimised to the tray via `--silent`. Same XDG autostart
  # mechanism as home/desktop/deskflow.nix: any .desktop file dropped
  # into ~/.config/autostart/ is honoured by every XDG-compliant DE
  # (KDE Plasma, GNOME, ...) during session startup.
  #
  # Rather than inlining a full copy of the desktop entry, we take the
  # one shipped by pkgs._1password-gui and rewrite only its Exec line
  # to append `--silent`. This way any upstream change to Name / Icon /
  # MimeType / Categories flows through automatically on the next `nhs`
  # -- our diff against upstream stays surgical (one flag, one line).
  xdg.configFile = {
    "systemd/user/gcr-ssh-agent.socket".text = "";
    "systemd/user/gcr-ssh-agent.service".text = "";

    "1Password/ssh/agent.toml".text = ''
      # Managed by home-manager (home/desktop/1password.nix). Do not
      # edit by hand -- changes are wiped on the next `nhs`.
      [[ssh-keys]]
      vault = "加密密钥"
    '';

    "autostart/1password.desktop".source = pkgs.substitute {
      src = "${pkgs._1password-gui}/share/applications/1password.desktop";
      substitutions = [
        "--replace-fail"
        "Exec=1password"
        "Exec=1password --silent"
      ];
    };
  };
}