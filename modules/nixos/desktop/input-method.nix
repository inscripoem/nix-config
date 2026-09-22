# Fcitx5 input method framework with Rime + Wanxiang schema.
# Lives in desktop/ because headless hosts don't need an input method.

{ pkgs, inputs, ... }:

let
  # Voice input addon (push-to-talk / hotkey trigger, coexists with Rime —
  # it registers as an fcitx5 Module, not an input method). The package
  # carries the addon library, vinput / vinput-gui CLIs and the daemon.
  vinput = inputs.fcitx5-vinput.packages.${pkgs.stdenv.hostPlatform.system}.default;
in

{
  i18n.inputMethod = {
    type = "fcitx5";
    enable = true;
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [
      fcitx5-gtk
      vinput
      qt6Packages.fcitx5-chinese-addons
      (fcitx5-rime.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ opencc ];
        postInstall = (old.postInstall or "") + ''
          wanxiangSrc=${inputs.rime-wanxiang}
          out=$out/share/rime-data

          # Wipe the wanxiang tree bundled with fcitx5-rime so that yaml,
          # lua and dicts all come from the same upstream commit pinned in
          # flake.lock. Non-wanxiang schemas shipped by fcitx5-rime stay.
          rm -f  $out/default.yaml $out/version.txt $out/custom_phrase.txt
          rm -f  $out/wanxiang*.yaml $out/custom_phrase.dict.yaml
          rm -rf $out/lua/wanxiang $out/lua/data
          # Bundled snapshot dirs come read-only from the store.
          if [ -d $out/opencc ]; then
            chmod -R u+w $out/opencc
            rm -rf $out/opencc
          fi

          install -Dm644 $wanxiangSrc/default.yaml $out/default.yaml
          shopt -s nullglob
          for f in $wanxiangSrc/wanxiang*.yaml; do
            install -Dm644 "$f" "$out/$(basename "$f")"
          done
          for f in $wanxiangSrc/version.txt $wanxiangSrc/custom_phrase.txt \
                   $wanxiangSrc/custom_phrase.dict.yaml; do
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
          # Upstream CI (release-build.sh build_opencc_wanxiang) compiles the
          # opencc txt dictionaries into ocd2 binaries at package time; the
          # git tree only carries the txt sources, and the schema's emoji /
          # s2t opencc configs only reference the ocd2 files. Replicate that
          # step or Deploy and those switches fail. Custom_* stay as text.
          if [ -d $wanxiangSrc/opencc ]; then
            mkdir -p $out/opencc
            cp -r $wanxiangSrc/opencc/. $out/opencc/
            chmod -R u+w $out/opencc
            (
              cd $out/opencc/wanxiang
              for f in *.txt; do
                case "$f" in Custom_*) continue ;; esac
                sed -i '/^#/d' "$f"
                opencc_dict -i "$f" -o "''${f%.txt}.ocd2" -f text -t ocd2
                rm -f "$f"
              done
            )
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

  environment.systemPackages = [ vinput ];

  # Upstream unit, mirrored declaratively: Type=dbus, wanted by
  # default.target. The daemon keeps the ASR model resident so trigger-key
  # latency stays low; the D-Bus activation file in the package resolves to
  # the same BusName.
  systemd.user.services.vinput-daemon = {
    after = [ "pipewire.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "dbus";
      BusName = "org.fcitx.Vinput";
      ExecStart = "${vinput}/bin/vinput-daemon";
    };
  };
}
