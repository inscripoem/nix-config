{ config, lib, pkgs, passwordStore, ... }:

let
  cfg = config.desktop.editors-gui;
in {
  options.desktop.editors-gui.traeCn.enable = lib.mkEnableOption "trae-cn editor" // {
    default = true;
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
    ];
  };
}
