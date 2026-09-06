{ ... }:

{
  # 6 is the newest value at install time (2026-09; valid range 1-6).
  # Pinned once, never bumped — it selects which release's defaults
  # apply to stateful data.
  system.stateVersion = 6;

  # Preserve the existing /etc/pam.d/sudo_local Touch ID behavior.
  security.pam.services.sudo_local.touchIdAuth = true;

  # macOS default shell is already zsh; this makes it declarative.
  programs.zsh.enable = true;
}
