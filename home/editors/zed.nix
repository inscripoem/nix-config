{ pkgs, ... }:
{
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
    # nix
    nixd
    nixfmt
  ];
}
