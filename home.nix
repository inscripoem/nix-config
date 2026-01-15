{ config, pkgs, ... }:

{
  # 注意修改这里的用户名与用户目录
  home.username = "inscripoem";
  home.homeDirectory = "/home/inscripoem";

  # 直接将当前文件夹的配置文件，链接到 Home 目录下的指定位置
  # home.file.".config/i3/wallpaper.jpg".source = ./wallpaper.jpg;

  # 递归将某个文件夹中的文件，链接到 Home 目录下的指定位置
  # home.file.".config/i3/scripts" = {
  #   source = ./scripts;
  #   recursive = true;   # 递归整个文件夹
  #   executable = true;  # 将其中所有文件添加「执行」权限
  # };

  # 直接以 text 的方式，在 nix 配置文件中硬编码文件内容
  # home.file.".xxx".text = ''
  #     xxx
  # '';

  # 通过 home.packages 安装一些常用的软件
  # 这些软件将仅在当前用户下可用，不会影响系统级别的配置
  # 建议将所有 GUI 软件，以及与 OS 关系不大的 CLI 软件，都通过 home.packages 安装
  home.packages = with pkgs;[
    # 如下是我常用的一些命令行工具，你可以根据自己的需要进行增删
    neofetch

    # archives
    zip
    xz
    unzip
    p7zip

    # utils
    ripgrep # recursively searches directories for a regex pattern
    jq # A lightweight and flexible command-line JSON processor
    yq-go # yaml processor https://github.com/mikefarah/yq
    eza # A modern replacement for ‘ls’
    fzf # A command-line fuzzy finder

    # nix related
    #
    # it provides the command `nom` works just like `nix`
    # with more details log output
    nix-output-monitor

    # system tools
    sysstat
    lm_sensors # for `sensors` command
    ethtool
    pciutils # lspci
    usbutils # lsusb
  ];

  programs.nix-index = {
    enable = true;
    enableFishIntegration = true;
  };

  # git 相关配置
  programs.git = {
    enable = true;
    userName = "inscripoem";
    userEmail = "changxuben@gmail.com";
  };

  programs.fish = {
    enable = true;
    shellAliases = {
      nhs = "nh os switch . -- --show-trace";
      ze = "zeditor .";
      z = "zoxide";
    };
  };

  # 启用 starship，这是一个漂亮的 shell 提示符
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  # alacritty - 一个跨平台终端，带 GPU 加速功能
  programs.alacritty = {
    enable = true;
    # 自定义配置
    settings = {
      env.TERM = "xterm-256color";
      font = {
        size = 12;
        normal.family = "Maple Mono NF CN";
      };
      scrolling.multiplier = 5;
      selection.save_to_clipboard = true;
    };
  };

  programs.wezterm = {
    enable = true;
    extraConfig = ''
      local wezterm = require('wezterm');
      local config = wezterm.config_builder();

      config.font = wezterm.font("Maple Mono NF CN");
      config.color_scheme = "catppuccin-frappe";
      config.hide_tab_bar_if_only_one_tab = true;
      config.default_prog = { os.getenv("SHELL"), "-l", "-c", "zellij attach --index 0 --create"};

      return config
    '';
  };

  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.zellij = {
    enable = true;
    # enableFishIntegration = true;
    settings = {
      keybindings = "normal";
      theme = "catppuccin-frappe";
      show_startup_tips = false;
    };
  };

  programs.bat = {
    enable = true;
    config.theme = "OneHalfDark";
  };

  programs.bash = {
    enable = true;
    enableCompletion = true;
    # TODO 在这里添加你的自定义 bashrc 内容
    bashrcExtra = ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"
    '';

    # TODO 设置一些别名方便使用，你可以根据自己的需要进行增删
    shellAliases = {
    };
  };

  programs.vscode = {
    enable = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      bbenoist.nix
      pkief.material-icon-theme
    ];
  };

  programs.zed-editor = {
    enable = true;
    extensions = ["nix" "toml"];
    userSettings = {
      lsp = {
        nix = {
          binary = {
            path_lookup = true;
          };
        };
      };
    };
  };
  nixGL.vulkan.enable = true;

  programs.plasma = {
    enable = true;
    hotkeys.commands."launch-wezterm" = {
      name = "Launch Wezterm";
      key = "Ctrl+Alt+T";
      command = "wezterm";
    };
  };

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "25.05";
}