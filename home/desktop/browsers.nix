# Ref: https://github.com/0xc000022070/zen-browser-flake/tree/main/examples
{pkgs, ...}: {
  programs.zen-browser = {
    enable = true;

    policies = {
      DisableAppUpdate = true;
      DisableTelemetry = true;
      DisablePocket = true;
    };

    profiles.default = {
      settings = {
        "zen.workspaces.continue-where-left-off" = true;
        "zen.view.compact.hide-tabbar" = true;
        "zen.urlbar.behavior" = "float";
      };

      # Zen theme store mods (referenced by UUID)
      # mods = [
      #   "e122b5d9-d385-4bf8-9971-e137809097d0" # No Top Sites
      #   "253a3a74-0cc4-47b7-8b82-996a64f030d5" # Floating History
      # ];

      search = {
        force = true;
        default = "ddg";
      };
    };
  };

  # 确保 MIME 和 $BROWSER 指向 Vivaldi
  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/http" = "vivaldi-stable.desktop";
    "x-scheme-handler/https" = "vivaldi-stable.desktop";
    "text/html" = "vivaldi-stable.desktop";
  };

  home.sessionVariables = {
    BROWSER = "vivaldi-stable";
  };
}
