{ ... }:

{
  targets.genericLinux.nixGL.vulkan.enable = true;

  # Ensure DISPLAY/WAYLAND_DISPLAY are available in the systemd user
  # session so that KRunner-launched apps (which go through systemd)
  # inherit them and don't crash with "no DISPLAY environment variable".
  systemd.user.sessionVariables = {
    DISPLAY = ":0";
    WAYLAND_DISPLAY = "wayland-0";
  };

  programs.plasma = {
    enable = true;
    hotkeys.commands."launch-wezterm" = {
      name = "Launch Wezterm";
      key = "Ctrl+Alt+T";
      command = "wezterm";
    };
    configFile."kwinrc"."Wayland"."VirtualKeyboard" = "org.fcitx.Fcitx5";
    # Let gnome-keyring own org.freedesktop.secrets; KWallet stays
    # only for KDE-internal features (NetworkManager, KMail, etc.)
    configFile."kwalletrc"."org.freedesktop.secrets"."apiEnabled" = false;
  };

  # xdg.portal is managed at the system level (see configuration.nix).
  # Declaring portals here would install per-user .portal files under
  # /etc/profiles/per-user/<user>/share, which appears earlier in
  # XDG_DATA_DIRS than /run/current-system/sw/share. xdg-desktop-portal
  # only scans the first matching directory, so a per-user xdg.portal
  # block would hide every system-level backend (notably
  # xdg-desktop-portal-kde, which provides RemoteDesktop required by
  # deskflow/synergy on Wayland). See:
  # https://discourse.nixos.org/t/hyprland-home-manager-module-breaks-portal-discovery-for-other-desktop-environments/78042
}
