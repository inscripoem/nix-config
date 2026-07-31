{ pkgs, commandLineArgs ? "" }:

let
  version = "2.3.62837";

  trae-cn = pkgs.stdenv.mkDerivation {
    pname = "trae-cn";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://lf-cdn.trae.com.cn/obj/trae-com-cn/pkg/app/releases/stable/${version}/linux/Trae_CN-linux-x64.deb";
      hash = "sha256-rwhdkmsxnG7ZIwswklVQ2G01O7N6eKyvcJDBqLrryMc=";
    };

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      dpkg
      makeWrapper
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc.lib
      libx11
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libxcb
      libxkbfile
      libxinerama
      libxcursor
      libxi
      libxscrnsaver
      libdrm
      mesa
      nss
      cups
      dbus
      libgcrypt
      libsecret
      gtk3
      webkitgtk_4_1
      libsoup_3
      pango
      cairo
      atk
      glib
      freetype
      fontconfig
      alsa-lib
      libpulseaudio
      libxshmfence
      libxkbcommon
      wayland
      libglvnd
      libnotify
      libappindicator-gtk3
      at-spi2-core
    ];

    runtimeDependencies = [ pkgs.libsecret ];

    autoPatchelfIgnoreMissingDeps = [ "libc.musl-x86_64.so.1" ];

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb --extract $src . 2>/dev/null || true
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      mkdir -p $out/share/applications
      mkdir -p $out/share/pixmaps
      mkdir -p $out/share/trae
      mkdir -p $out/lib

      cp -r usr/bin/* $out/bin/ 2>/dev/null || true
      cp -r usr/share/applications/* $out/share/applications/ 2>/dev/null || true
      cp -r usr/share/pixmaps/* $out/share/pixmaps/ 2>/dev/null || true
      cp -r usr/share/icons/* $out/share/pixmaps/ 2>/dev/null || true
      cp -r usr/share/trae-cn/* $out/share/trae/ 2>/dev/null || true
      cp -r usr/lib/* $out/lib/ 2>/dev/null || true
      cp -r opt $out/ 2>/dev/null || true

      find $out -name "chrome-sandbox" -exec chmod 0755 {} \; 2>/dev/null || true
      find $out -name "trae-cn" -type f -exec chmod 0755 {} \; 2>/dev/null || true

      autoPatchelf $out

      # Create launcher script
      if [ -f "$out/share/trae/trae-cn" ]; then
        echo '#!/bin/sh' > $out/bin/trae-cn
        echo 'export ELECTRON_FORCE_IS_PACKAGED=1' >> $out/bin/trae-cn
        echo 'export ELECTRON_DISABLE_SANDBOX=1' >> $out/bin/trae-cn
        echo 'export DISABLE_GPU_SANDBOX=1' >> $out/bin/trae-cn
        echo "exec $out/share/trae/trae-cn --no-sandbox \"\$@\"" >> $out/bin/trae-cn
        chmod +x $out/bin/trae-cn
      fi

      # Fix desktop file
      if [ -f "$out/share/applications/trae-cn.desktop" ]; then
        sed -i "s|Exec=.*|Exec=$out/bin/trae-cn|g" $out/share/applications/trae-cn.desktop
      fi

      # Expose commandLineArgs override surface (mirrors vivaldi/vscode API).
      # wrapProgram appends the flags into argv before "$@", so the underlying
      # Electron main process receives them like a native CLI arg.
      wrapProgram $out/bin/trae-cn \
        --add-flags ${pkgs.lib.escapeShellArg commandLineArgs}

      runHook postInstall
    '';

    meta = with pkgs.lib; {
      description = "Trae CN - AI-powered IDE by ByteDance";
      homepage = "https://www.trae.com.cn";
      license = licenses.unfree;
      platforms = platforms.linux;
      mainProgram = "trae-cn";
    };
  };
in
trae-cn
