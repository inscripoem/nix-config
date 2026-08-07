# Fcitx5 input method framework with Rime + Wanxiang schema.
# Lives in desktop/ because headless hosts don't need an input method.

{ pkgs, inputs, ... }:

{
  i18n.inputMethod = {
    type = "fcitx5";
    enable = true;
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [
      fcitx5-gtk
      qt6Packages.fcitx5-chinese-addons
      (fcitx5-rime.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          wanxiangSrc=${inputs.rime-wanxiang}
          out=$out/share/rime-data

          # Wipe the wanxiang tree bundled with fcitx5-rime so that yaml,
          # lua and dicts all come from the same upstream commit pinned in
          # flake.lock. Non-wanxiang schemas shipped by fcitx5-rime stay.
          rm -f  $out/default.yaml $out/version.txt $out/custom_phrase.txt
          rm -f  $out/wanxiang*.yaml
          rm -rf $out/lua/wanxiang $out/lua/data

          install -Dm644 $wanxiangSrc/default.yaml $out/default.yaml
          shopt -s nullglob
          for f in $wanxiangSrc/wanxiang*.yaml; do
            install -Dm644 "$f" "$out/$(basename "$f")"
          done
          for f in $wanxiangSrc/version.txt $wanxiangSrc/custom_phrase.txt; do
            [ -f "$f" ] && install -Dm644 "$f" "$out/$(basename "$f")" || true
          done
          if [ -d $wanxiangSrc/lua ]; then
            mkdir -p $out/lua
            cp -r $wanxiangSrc/lua/. $out/lua/
            chmod -R u+w $out/lua
          fi
          if [ -d $wanxiangSrc/dicts ]; then
            mkdir -p $out/dicts
            for f in $wanxiangSrc/dicts/*; do
              [ -f "$f" ] && install -Dm644 "$f" "$out/dicts/$(basename "$f")" || true
            done
          fi
          shopt -u nullglob
        '';
      }))
      catppuccin-fcitx5
    ];
    # Activate catppuccin-mocha-mauve theme with matching font size.
    # Fcitx5 ignores theme.conf Font → must set in globalSection explicitly.
    fcitx5.settings.addons.classicui.globalSection = {
      Theme = "catppuccin-mocha-mauve";
      Font = ''"Sans 13"'';
    };
  };
}
