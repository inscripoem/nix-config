# User-level fcitx5 classicui (candidate panel) theming.
#
# Deliberately at the user level: WeChat's client-side candidate panel
# (home/desktop/social.nix) reads ONLY ~/.config/fcitx5 — its minimal
# embedded config reader has no XDG_CONFIG_DIRS cascade, so a system-wide
# /etc/xdg copy never reaches it (and exposing /etc/xdg into its bwrap
# sandbox breaks WeChat login outright; see the wechat overlay in
# pkgs/default.nix). This file is the single source of truth for
# Theme/Font; the theme data itself comes from the fcitx5-mellow-themes
# addon declared in modules/nixos/desktop/input-method.nix
# (catppuccin-fcitx5 stays there as an instant-rollback alternative).
#
# The dark variant is pinned directly on Theme= instead of using the
# DarkTheme/UseDarkTheme follow-system keys: WeChat's embedded panel
# reader is not known to implement those, so Theme= must carry the dark
# variant for it to render the same look.
{
  xdg.configFile."fcitx5/conf/classicui.conf".text = ''
    Font="Sans 13"
    Theme=mellow-wechat-dark
  '';
}
