{
  programs.nix-index = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };

  # Provided by nix-index-database: comma runs commands without installing
  # (`, cmd`), and programs.nix-index.package is swapped for a wrapper
  # reading the weekly prebuilt database — no local `nix-index` scan
  # needed; the database refreshes with flake update.
  programs.nix-index-database.comma.enable = true;
}
