# Linux-patched build of orca from the llm-agents input: close-to-tray
# (./orca-tray.py, four byte-length-neutral asar edits) plus a
# silent-start env gate (./orca-silent-start.py, one 31-byte insert via
# full asar re-layout), an ORCA_SILENT_START wrapper twin of bin/orca-ide
# for XDG autostart, the matching autostart desktop template, and a
# Wayland IME flag wrapper of bin/orca-ide (fcitx5-vinput#464).
#
# This is a function over the upstream derivation, not a package of its
# own: the flake wiring (which orca to feed in) lives in home/packs/ai/orca.nix
# and version bumps ride llm-agents flake updates, so there is no
# update-versions.sh section (same exemption class as the workbuddy
# autostart twin). Both patch scripts assert their anchors; an upstream
# release that reshuffles app.asar fails this build loudly.
{
  orca,
  python3,
  stdenv,
}:
if !stdenv.hostPlatform.isLinux then
  orca
else
  orca.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ python3 ];
    postInstall = (old.postInstall or "") + ''
      python3 ${./orca-tray.py} $out/lib/Orca/resources/app.asar
      python3 ${./orca-silent-start.py} $out/lib/Orca/resources/app.asar

      # Autostart twin of bin/orca-ide: identical entry point plus the
      # ORCA_SILENT_START env gate consumed by the asar patch above
      # (boots to tray only; manual launches keep showing the window).
      echo '#!/bin/sh' > $out/bin/orca-autostart
      echo 'export ORCA_SILENT_START=1' >> $out/bin/orca-autostart
      echo "exec $out/bin/orca-ide \"\$@\"" >> $out/bin/orca-autostart
      chmod +x $out/bin/orca-autostart
    '';
    # The autostart desktop template needs the shipped entry, which
    # copyDesktopItems only drops after postInstall — chain postFixup
    # (keeping upstream's autoPatchelf) and generate it there.
    postFixup = (old.postFixup or "") + ''
      mkdir -p $out/share/orca
      sed "s|Exec=.*|Exec=$out/bin/orca-autostart %U|" \
        $out/share/applications/orca-ide.desktop \
        > $out/share/orca/orca-autostart.desktop

      # Wayland IME flags for the embedded xterm.js terminal, replicated
      # verbatim from the fcitx5-vinput#464 maintainer recipe and verified
      # on niri 2026-10-30: with these flags, stock vinput dictation (bare
      # commit_string) lands. The ozone pair is likely a no-op (orca is
      # already a native Wayland client) but is kept for fidelity with the
      # tested configuration. Wrapper interception, not a desktop-file edit,
      # so every caller — launcher entry, the orca-autostart twin, tray
      # relaunch — inherits the flags; a missing upstream bin/orca-ide
      # fails the build loudly.
      mv $out/bin/orca-ide $out/bin/.orca-ide-real
      {
        echo '#!/bin/sh'
        echo 'export ORCA_IDE_OZONE_PLATFORM=wayland'
        echo "exec $out/bin/.orca-ide-real --enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3 \"\$@\""
      } > $out/bin/orca-ide
      chmod +x $out/bin/orca-ide
    '';
  })
