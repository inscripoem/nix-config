{ pkgs, passwordStore, ... }:

{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode.override {
      commandLineArgs = "--password-store=${passwordStore}";
    };
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
    # Wrap trae-cn to inject the desktop-group keyring backend flag without
    # polluting pkgs/trae-cn.nix (which stays a plain deb repackager).
    (symlinkJoin {
      name = "trae-cn-wrapped";
      paths = [ trae-cn ];
      nativeBuildInputs = [ makeBinaryWrapper ];
      postBuild = ''
        wrapProgram $out/bin/trae-cn \
          --add-flags "--password-store=${passwordStore}"
        # .desktop is a symlink into the read-only store; replace with a
        # writable copy so we can point Exec= at the wrapped binary.
        rm $out/share/applications/trae-cn.desktop
        install -m 0644 ${trae-cn}/share/applications/trae-cn.desktop \
          $out/share/applications/trae-cn.desktop
        substituteInPlace $out/share/applications/trae-cn.desktop \
          --replace-quiet "${trae-cn}/bin/trae-cn" "$out/bin/trae-cn"
      '';
      inherit (trae-cn) meta;
    })
  ];
}
