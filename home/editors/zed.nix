{
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
}
