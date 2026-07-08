{ pkgs, ... }:

{
  programs.vscode = {
    enable = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      bbenoist.nix
      pkief.material-icon-theme
    ];
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
    trae-cn
  ];
}
