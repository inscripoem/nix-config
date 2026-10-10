final: prev: {
  harmonyos-sans = final.callPackage ./harmonyos-sans.nix { };
  siyuan = final.callPackage ./siyuan.nix { };
  "trae-cn" = final.callPackage ./trae-cn.nix { };
  "qoder-cn" = final.callPackage ./qoder-cn.nix { };
  "qoder-cn-ide" = final.callPackage ./qoder.nix { };
  workbuddy = final.callPackage ./workbuddy.nix { };
  "cc-switch" = final.callPackage ./cc-switch.nix { };
  notion-electron = final.callPackage ./notion-electron.nix { };
  glances = final.callPackage ./glances.nix { originalGlances = prev.glances; };
  rebarstate = final.callPackage ./rebarstate.nix { };

  # nixpkgs fetches wechat's x86_64 AppImage from web.archive.org (Tencent
  # does not keep history versions); that fetch failed through this
  # network's proxy at pin time (TLS resets, possibly a dirty exit node),
  # and upstream still packages 4.1.1.8 while the official site ships
  # 4.1.13.x. Re-invoke upstream's linux.nix with the current version from
  # the mirror archive adopted by nixpkgs#565201;
  # the hash was computed from a direct official-CDN download and matches
  # the mirror's checksum file. (The by-name package.nix wrapper is not
  # arg-overridable, hence the direct call.) To bump: `just update wechat`
  # rewrites version, mirror URL and hash from the mirror's latest release.
  # Drop this override entirely once nixpkgs#560225 (wechat 4.1.13.x)
  # lands in unstable.
  wechat =
    let
      wechatFhs = prev.callPackage (prev.path + "/pkgs/by-name/we/wechat/linux.nix") {
        pname = "wechat";
        version = "4.1.13.23";
        src = final.fetchurl {
          url = "https://github.com/Rodert/wechat-linux-versions/releases/download/v4.1.13.23/WeChatLinux_x86_64.AppImage";
          hash = "sha256-T1StKQLs1vb9xWgLc1R/gNVCO/RwsBI3pXmi5bPK7us=";
        };
        meta = prev.wechat.meta;
      };
    in
    if prev.stdenv.hostPlatform.system == "x86_64-linux" then
      prev.symlinkJoin {
        name = wechatFhs.name;
        paths = [ wechatFhs ];
        nativeBuildInputs = [ prev.makeWrapper ];
        passthru = { inherit (wechatFhs) version; };
        # WeChat's UI toolkit is neither Qt nor GTK (the main binary only
        # links glib/dbus): it implements the fcitx5 D-Bus input context
        # protocol itself, but only activates it when QT_IM_MODULE=fcitx
        # (value must be "fcitx", not "fcitx5"). fcitx5.waylandFrontend
        # deliberately leaves QT_IM_MODULE unset system-wide, so export it
        # here, gated on XMODIFIERS the same way the Flathub repack does.
        #
        # NOTE: do NOT try to expose the host's /etc/xdg (fcitx5
        # classicui.conf for theming) inside this sandbox: replacing the
        # rootfs's copy breaks WeChat login outright (login webview hangs).
        # If theming is ever revisited, the lever is a user-level
        # ~/.config/fcitx5/conf/classicui.conf — /home is bound wholesale.
        postBuild = ''
          wrapProgram $out/bin/wechat \
            --run 'case "$XMODIFIERS" in *fcitx*) export QT_IM_MODULE=fcitx GTK_IM_MODULE=fcitx ;; esac'
        '';
      }
    else
      prev.wechat;

  ww-manager = final.callPackage ./ww-manager.nix { };
}
