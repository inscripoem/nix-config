# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

let
  publicKey = builtins.readFile ./keys/ssh-ed25519.pub;
in

{

  imports = [
    ./system/1password.nix
    ./system/gaming.nix
  ];

  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Asia/Shanghai";

  # Select internationalisation properties.
  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ALL = "en_US.UTF-8";
      LANGUAGE = "en_US.UTF-8";
    };
    supportedLocales = [
      "en_US.UTF-8/UTF-8"
      "C.UTF-8/UTF-8"
      "zh_CN.UTF-8/UTF-8"
      "zh_TW.UTF-8/UTF-8"
    ];
    inputMethod = {
      type = "fcitx5";
      enable = true;
      fcitx5.waylandFrontend = true;
      fcitx5.addons = with pkgs; [
        fcitx5-gtk
        qt6Packages.fcitx5-chinese-addons
        fcitx5-rime
        catppuccin-fcitx5
      ];
    };
  };

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Use gnome-keyring as the Secret Service provider (org.freedesktop.secrets)
  # so libsecret-based apps (trae-cn, vivaldi, chromium, vscode, git) get an
  # auto-unlocked keyring at login. KWallet stays for KDE-internal use only.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;

  # xdg-desktop-portal routing. xdg-desktop-portal-gtk gets pulled in by some
  # apps but it does NOT implement RemoteDesktop, so without an explicit
  # preference the router can fail to find a backend (e.g. deskflow client on
  # Wayland: "No such interface org.freedesktop.portal.RemoteDesktop").
  # Force every interface on a KDE session to the kde backend; KWin provides
  # RemoteDesktop via libei.
  xdg.portal = {
    enable = true;
    config.kde.default = [ "kde" ];
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.inscripoem = {
    isNormalUser = true;
    description = "Brandon Chang";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [
      kdePackages.kate
      #  thunderbird
    ];
    openssh.authorizedKeys.keys = [ publicKey ];
    shell = pkgs.zsh;
  };

  users.users.root.openssh.authorizedKeys.keys = [ publicKey ];

  # Install firefox.
  programs.firefox.enable = true;

  programs.fish.enable = true;
  programs.zsh.enable = true;

  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
    flake = "/home/inscripoem/nix-config";
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # Users allowed to push extra substituters / require-sigs=false / etc.
    # Required so flakes (e.g. llm-agents.nix) can be built without warnings.
    trusted-users = [
      "root"
      "inscripoem"
    ];
    substituters = [
      "https://cache.nixos.org/"
      # Real binary caches inside CERNET (verified nix-cache-info reachable).
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://mirror.sjtu.edu.cn/nix-channels/store"
      # numtide binary cache for llm-agents.nix (claude-code, codex, opencode, ...)
      "https://cache.numtide.com"
    ];
    trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
    fallback = true;
  };
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    git
    maple-mono.NF-CN
  ];
  environment.variables.EDITOR = "vim";

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

}
