# System-side 1Password integration.
#
# Why this lives at the system level (and not under home/):
#   - `programs._1password{,-gui}` are NixOS modules, not home-manager
#     modules. They register a setgid wrapper for the browser bridge
#     (`/run/wrappers/bin/1Password-BrowserSupport`), a system group
#     (`onepassword`), and a polkit policy file under `/etc/polkit-1/`.
#     home-manager can write none of these.
#   - `environment.etc."1password/custom_allowed_browsers"` lands in
#     `/etc/`, also strictly system territory.
#
# User-facing pieces (the SSH agent socket consumer wiring, the
# `agent.toml` vault allowlist, etc.) live in `home/secrets/1password.nix`.

{ config, lib, ... }:
let cfg = config.modules.capabilities."1password";
in {
  options.modules.capabilities."1password".enable =
    lib.mkEnableOption "1Password system integration";
  config = lib.mkIf cfg.enable {
    # GUI app + CLI (`op`). The GUI module installs the setuid-wrapped
    # browser-integration helper and brings up the built-in SSH agent
    # socket at ~/.1password/agent.sock, which the home-side config wires
    # into $SSH_AUTH_SOCK and ssh_config's IdentityAgent.
    # `polkitPolicyOwners` whitelists who can drive the GUI from a CLI
    # (`op signin --account ...` etc.).
    programs._1password.enable = true;
    programs._1password-gui = {
      enable = true;
      polkitPolicyOwners = [ "inscripoem" ];
    };

    # Allowlist for the 1Password browser-integration native-messaging
    # bridge. Firefox/Chrome/Brave are recognised by the GUI by default;
    # Vivaldi (and any other Chrome fork installed via NixOS rather than
    # via Flatpak/Snap) must be opted in by process name, otherwise the
    # extension shows "1Password is locked" and refuses to auto-fill.
    # Process name comes from `ps aux | grep vivaldi` -> vivaldi-bin.
    # See https://wiki.nixos.org/wiki/1Password#Unlocking_browser_extensions
    # and docs/ssh-agent.md §9.
    environment.etc."1password/custom_allowed_browsers" = {
      text = ''
        vivaldi-bin
      '';
      mode = "0755";
    };
  };
}
