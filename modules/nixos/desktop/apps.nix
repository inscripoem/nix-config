# Desktop-only applications that have no reason to exist on headless hosts.

{ lib, pkgs, ... }:

let
  # Tela-style redraws for icon names the upstream themes get wrong or lack
  # entirely. Key = lookup name (desktop-file Icon= / notification app_icon),
  # value = SVG drawn in the Tela-circle template (accent circle + 15% white
  # inner ring + glyph). Source artwork: orca/zcode traced from the apps'
  # own product icons, notion lifted from Papirus, the rest traced from the
  # apps' shipped SVGs.
  themeIcons = {
    "orca" = ./icons/orca.svg; # orca-ide's notifications send bare app_icon "orca", which collides with GNOME Orca's person icon
    "zcode" = ./icons/zcode.svg;
    "notion-electron" = ./icons/notion.svg;
    "de.feschber.LanMouse" = ./icons/lanmouse.svg;
    "vinput-gui" = ./icons/vinput.svg;
    "ai.storyteller.photocraft" = ./icons/photocraft.svg;
    "deepseek-ai-dsh-desktop" = ./icons/dsh.svg;
    "org.zrythm.Zrythm" = ./icons/zrythm.svg;
  };

  installThemeIcons = variants: rel: ''
    for v in ${lib.concatStringsSep " " variants}; do
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (icon: file:
        ''install -Dm644 ${file} "$out/share/icons/''${v}/${rel}/${icon}.svg"''
      ) themeIcons)}
    done
  '';
in
{
  environment.systemPackages = with pkgs; [
    kdePackages.kate
    papirus-icon-theme
    (tela-circle-icon-theme.overrideAttrs (old: {
      postInstall = (old.postInstall or "")
        + installThemeIcons [ "Tela-circle" "Tela-circle-dark" "Tela-circle-light" ] "scalable/apps"
        # Alias names the apps ask for onto Tela's own art: ardour9 is
        # Ardour's versioned Icon=, sunshine's desktop file uses the fully
        # qualified dev.lizardbyte.app.Sunshine while Tela ships "sunshine".
        + ''
          for v in Tela-circle Tela-circle-dark Tela-circle-light; do
            cp "$out/share/icons/''${v}/scalable/apps/ardour.svg" \
               "$out/share/icons/''${v}/scalable/apps/ardour9.svg"
            cp "$out/share/icons/''${v}/scalable/apps/sunshine.svg" \
               "$out/share/icons/''${v}/scalable/apps/dev.lizardbyte.app.Sunshine.svg"
          done
        '';
    }))
    (colloid-icon-theme.overrideAttrs (old: {
      postInstall = (old.postInstall or "")
        + installThemeIcons [ "Colloid" "Colloid-Dark" "Colloid-Light" ] "apps/scalable";
    }))
    # Expose GLib GSettings schemas (org.gnome.desktop.interface etc.) so the
    # GDK Wayland GSettings binding activates. DMS writes
    # `gsettings set org.gnome.desktop.interface icon-theme` on theme switch,
    # but it silently fails without schemas — with them, Qt/GTK apps receive
    # realtime icon-theme updates.
    gsettings-desktop-schemas
  ];
}
