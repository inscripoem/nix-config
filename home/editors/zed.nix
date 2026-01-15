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
    };
  };
  # LSP requirements
  home.packages = with pkgs; [
    # nix
    nil
    nixd
    nixfmt
  ];
}
