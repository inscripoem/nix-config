{ config, pkgs, inputs, ... }:

{
  time.timeZone = "Asia/Shanghai";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ALL = "en_US.UTF-8";
      LANGUAGE = "en_US.UTF-8";
    };
    supportedLocales = [
      "en_US.UTF-8/UTF-8"
      "C.UTF-8/UTF-8"
      "zh_CN.UTF-8/UTF-8"
      "zh_TW.UTF-8/UTF-8"
    ];
    inputMethod = {
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

            # Replace built-in default.yaml with wanxiang's latest from upstream
            rm -f $out/default.yaml
            cp $wanxiangSrc/default.yaml $out/default.yaml

            # Copy wanxiang schema/dict/aux files (ignore globs that match nothing)
            shopt -s nullglob
            for f in $wanxiangSrc/wanxiang*.yaml; do cp -n "$f" $out/; done
            for f in $wanxiangSrc/version.txt $wanxiangSrc/custom_phrase.txt; do
              [ -f "$f" ] && cp -n "$f" $out/ || true
            done

            # Lua scripts (wanxiang schema requires these)
            if [ -d $wanxiangSrc/lua ]; then
              mkdir -p $out/lua
              cp -r $wanxiangSrc/lua/. $out/lua/
            fi

            # Dict files (wanxiang.dict.yaml imports from dicts/)
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
  };
}
