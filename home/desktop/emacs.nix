{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.desktop.emacs;
in
{
  options.desktop.emacs.enable = lib.mkEnableOption "Emacs (pgtk build, bundled org-mode) with its systemd daemon";

  config = lib.mkIf cfg.enable {
    programs.emacs = {
      enable = true;
      # pgtk: native Wayland build — no XWayland round-trip under niri, and
      # IME goes through the text-input protocol instead of XIM.
      package = pkgs.emacs-pgtk;
      # org-mode ships built in (9.8+ on Emacs 31). Deliberately no ELPA org
      # override: a newer org shadows the built-in one and autoload ordering
      # between the two is a classic breakage.
    };

    services.emacs = {
      enable = true;
      # Start the daemon only once the graphical session is up, so the pgtk
      # daemon inherits WAYLAND_DISPLAY; ordered against default.target it
      # would race the compositor and open frames on the wrong backend.
      startWithUserSession = "graphical";
      # Launcher/desktop entries open emacsclient frames into the daemon
      # (instant open) instead of cold-starting a competing instance.
      client.enable = true;
    };
  };
}
