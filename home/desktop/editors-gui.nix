{ config, lib, pkgs, passwordStore, ... }:

let
  cfg = config.desktop.editors-gui;
in {
  options.desktop.editors-gui.traeCn.enable = lib.mkEnableOption "trae-cn editor" // {
    default = true;
  };

  # Opt-in: large unfree IDE, currently only enabled on briefcase.
  options.desktop.editors-gui.qoderCnIde.enable = lib.mkEnableOption "qoder-cn-ide editor" // {
    default = false;
  };

  config = {
    programs.vscode = {
      enable = true;
      package = pkgs.vscode.override {
        commandLineArgs = "--password-store=${passwordStore}";
      };
      mutableExtensionsDir = true;
    };

    programs.zed-editor = {
      enable = true;
      extensions = [
        "nix"
        "toml"
        "python"
      ];
      userSettings = {
        colorize_brackets = true;
        autosave = "on_focus_change";
        languages = {
          "Nix" = {
            language_servers = [
              "nixd"
              "!nil"
            ];
          };
        };
      };
    };

    # LSP requirements
    home.packages = with pkgs; [
      nixd
      nixfmt
      heynote
    ] ++ lib.optionals cfg.traeCn.enable [
      (trae-cn.override {
        commandLineArgs = "--password-store=${passwordStore}";
      })
    ] ++ lib.optionals cfg.qoderCnIde.enable [
      (qoder-cn-ide.override {
        commandLineArgs = "--password-store=${passwordStore}";
      })
    ];
  };
}
