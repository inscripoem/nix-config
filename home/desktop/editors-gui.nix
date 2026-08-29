{ pkgs, passwordStore, ... }:

{
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
    (trae-cn.override {
      commandLineArgs = "--password-store=${passwordStore}";
    })
  ];
}
