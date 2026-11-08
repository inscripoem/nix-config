{ config, lib, pkgs, ... }:

{
  # Use gnome-keyring as the Secret Service provider (org.freedesktop.secrets)
  # so libsecret-based apps (vivaldi, chromium, vscode, git) get an
  # auto-unlocked keyring at login. KWallet stays for KDE-internal use only.
  services.gnome.gnome-keyring.enable = true;

  # Non-graphical sessions must not claim the login keyring. Tailscale SSH
  # authenticates through /bin/login and can appear before greetd; its
  # pam_gnome_keyring auto_start previously left the daemon attached to the
  # TTY session, so greetd could not unlock the same keyring in the graphical
  # session. Keep the graphical greetd rules below and disable only the
  # terminal/SSH PAM integrations.
  security.pam.services.login.enableGnomeKeyring = lib.mkForce false;
  security.pam.services.sshd.enableGnomeKeyring = lib.mkForce false;

  # greetd is the display manager; its PAM service covers both greeter
  # authentication and the user session handoff. The greetd module opts out
  # of the default PAM rule set (`useDefaultRules = false`), which is where
  # `enableGnomeKeyring` would inject the keyring rules — so append them to
  # the custom ruleset directly, just after the `login` substack so the
  # entered password is already available as the authtok. Same shape as the
  # default ruleset's gnome_keyring entries: auth unlocks the keyring,
  # session starts the daemon (auto_start).
  security.pam.services.greetd.rules.auth.gnome_keyring = {
    order = config.security.pam.services.greetd.rules.auth.login.order + 10;
    control = "optional";
    modulePath = "${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so";
  };
  security.pam.services.greetd.rules.session.gnome_keyring = {
    order = config.security.pam.services.greetd.rules.session.login.order + 10;
    control = "optional";
    modulePath = "${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so";
    settings = { auto_start = true; };
  };
}
