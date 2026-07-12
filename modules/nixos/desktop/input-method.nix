# Fcitx5 input method framework with Rime + Wanxiang schema.
# Lives in desktop/ because headless hosts don't need an input method.

{ config, pkgs, inputs, ... }:

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
          rm -f $out/default.yaml
          cp $wanxiangSrc/default.yaml $out/default.yaml
          shopt -s nullglob
          for f in $wanxiangSrc/wanxiang*.yaml; do cp -n "$f" $out/; done
          for f in $wanxiangSrc/version.txt $wanxiangSrc/custom_phrase.txt; do
            [ -f "$f" ] && cp -n "$f" $out/ || true
          done
          if [ -d $wanxiangSrc/lua ]; then
            mkdir -p $out/lua
            cp -r $wanxiangSrc/lua/. $out/lua/
          fi
          if [ -d $wanxiangSrc/dicts ]; then
            mkdir -p $out/dicts
            for f in $wanxiangSrc/dicts/*; do
              [ -f "$f" ] && cp -n "$f" $out/dicts/ || true
            done
          fi
          shopt -u nullglob
        '';
      }))
      catppuccin-fcitx5
    ];
  };
}
