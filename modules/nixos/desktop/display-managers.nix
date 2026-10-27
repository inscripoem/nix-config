{ pkgs, vars, ... }:

{
  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # greetd + Dux Greeter (dms-greeter): the DMS-native login screen running
  # inside a niri greeter session. Replaces the X11 SDDM setup, which was
  # retained only as the Sunshine XShm-era known-good greeter; KMS capture
  # streams any greeter backend (see docs/remote-desktop.md §2).
  #
  # Session picking works on NixOS without extra plumbing: greetd's default
  # source_profile handling sources /etc/profile → /etc/set-environment
  # before exec'ing the greeter, which exports XDG_DATA_DIRS including the
  # displayManager sessionData dir — dms-greeter enumerates niri.desktop and
  # plasma.desktop from there and starts the chosen one through greetd.
  services.displayManager.dux-greeter = {
    enable = true;
    compositor.name = "niri";
    # Compositor config for the greeter session itself (not user sessions).
    # Left empty: dms-greeter generates its own minimal niri config that
    # just spawns the greeter UI.
    # Mirror the desktop shell's wallpaper/theme/session settings into
    # /var/lib/dms-greeter on every generation switch so the greeter looks
    # like the daily desktop.
    configHome = "/home/${vars.username}";
    # Keep logs at /tmp/dms-greeter.log while the switch is fresh; drop
    # once the greeter has proven stable across a few rebuilds.
    logs.save = true;
  };
  # DMS greeter lists users/avatars through accountsservice.
  services.accounts-daemon.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  # The old pin was "plasmax11": the user session then shared SDDM's X
  # display :0, letting the user-level Sunshine XShm-capture it for the
  # remote handoff. KDE removed the X11 session upstream and nixpkgs now
  # ships only the Wayland "plasma" one. Sunshine switched to KMS capture
  # (capSysAdmin, see capabilities/sunshine.nix), so every session is
  # streamable; niri stays the default as the daily session.
  services.desktopManager.plasma6.enable = true;
  services.displayManager.defaultSession = "niri";

  # plasma6 turns the GNOME Orca screen reader on by default (upstream
  # `services.orca.enable = mkDefault true`), which installs orca.desktop
  # under the bare id "orca" — the same id orca-ide reports as its window
  # app-id and notification app_icon, so launchers and DMS resolve the
  # wrong desktop entry. No screen reader is used here; drop the package.
  services.orca.enable = false;

  # No auto-login. Sunshine runs as a root system service
  # (sunshine-greeter) that captures the greeter before anyone logs in —
  # Moonlight connects, sees the DMS greeter, you type the password, and
  # the session hands off to the user-level Sunshine service. This avoids
  # the auto-login + keyring problem (KWallet / gnome-keyring never unlock
  # without a PAM password, which breaks WiFi auto-connect and Vivaldi's
  # cookie store). See docs/remote-desktop.md.

  # Enable niri - scrollable-tiling Wayland compositor.
  # Use niri-unstable from the niri-flake overlay to get newer actions like
  # maximize-window-to-edges that are not yet in the stable release.
  programs.niri = {
    enable = true;
    package = pkgs.niri-unstable;
  };
  # niri-flake hardcodes a polkit-kde-agent user service into every niri
  # session. polkitd allows exactly one registered agent per session, so the
  # always-running KDE agent beats the one DMS (quickshell) registers on shell
  # startup, and pkexec prompts render Kirigami-styled (light window, dark
  # buttons) instead of following DMS's theme. Disable it: DMS's built-in
  # PolkitAgent is the sole agent under niri; Plasma sessions are unaffected —
  # the plasma6 module ships the same agent via its OnlyShowIn=KDE autostart
  # entry, which niri sessions skip.
  systemd.user.services.niri-flake-polkit.enable = false;
  # niri session doesn't pull GNOME; install nautilus so
  # xdg-desktop-portal-gnome (≥ v47) can back its FileChooser.
  # See https://github.com/YaLTeR/niri/wiki/Important-Software#portals.
  environment.systemPackages = [ pkgs.nautilus ];

  # LocalSend needs port 53317 on both TCP (file transfer) and UDP
  # (multicast peer discovery).
  networking.firewall.allowedTCPPorts = [ 53317 ];
  networking.firewall.allowedUDPPorts = [ 53317 ];
}