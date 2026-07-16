{ pkgs, ... }:

{
  targets.genericLinux.nixGL.vulkan.enable = true;

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

  home.packages = with pkgs; [
    deskflow
    wl-clipboard
  ];

  xdg.configFile."autostart/nm-applet.desktop".text = ''
    [Desktop Entry]
    Hidden=true
  '';

  xdg.configFile."autostart/org.deskflow.deskflow.desktop".source =
    "${pkgs.deskflow}/share/applications/org.deskflow.deskflow.desktop";
}
