{ pkgs, commandLineArgs ? "" }:

let
  version = "1.33.0";

  qoder-cn-ide = pkgs.stdenv.mkDerivation {
    pname = "qoder-cn-ide";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://qoder-ide-cn.oss-cn-hangzhou.aliyuncs.com/qoder/release/${version}/qoder-cn-ide_amd64.deb";
      hash = "sha256-WynZqiL1IiGdB0Z9oi+HzVhTjF+g/MDWmUx1S3JVD8o=";
    };

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      dpkg
      makeWrapper
      patchelf
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
      mkdir -p $out/share/qoder

      cp -r usr/share/applications/* $out/share/applications/ 2>/dev/null || true
      cp -r usr/share/pixmaps/* $out/share/pixmaps/ 2>/dev/null || true
      cp -r usr/share/qoder-cn-ide/* $out/share/qoder/ 2>/dev/null || true

      find $out -name "chrome-sandbox" -exec chmod 0755 {} \; 2>/dev/null || true
      find $out -name "qoder-cn-ide" -type f -exec chmod 0755 {} \; 2>/dev/null || true

      autoPatchelf $out

      # Chromium's GPU process dlopens libGL/libEGL/libGLESv2 at runtime, so
      # autoPatchelf alone never sees them; force them into DT_NEEDED with
      # absolute store paths (same trick as nixpkgs vscode) or hardware
      # acceleration silently falls back to software rendering.
      patchelf \
        --add-needed ${pkgs.libglvnd}/lib/libGLESv2.so.2 \
        --add-needed ${pkgs.libglvnd}/lib/libGL.so.1 \
        --add-needed ${pkgs.libglvnd}/lib/libEGL.so.1 \
        $out/share/qoder/qoder-cn-ide

      # Create launcher script
      if [ -f "$out/share/qoder/qoder-cn-ide" ]; then
        echo '#!/bin/sh' > $out/bin/qoder-cn
        echo 'export ELECTRON_FORCE_IS_PACKAGED=1' >> $out/bin/qoder-cn
        echo 'export ELECTRON_DISABLE_SANDBOX=1' >> $out/bin/qoder-cn
        echo 'export DISABLE_GPU_SANDBOX=1' >> $out/bin/qoder-cn
        echo "exec $out/share/qoder/qoder-cn-ide --no-sandbox \"\$@\"" >> $out/bin/qoder-cn
        chmod +x $out/bin/qoder-cn
      fi

      # Fix desktop files (prefix match keeps the url-handler's
      # `--new-window %F` arguments intact)
      sed -i "s|Exec=/usr/share/qoder-cn-ide/qoder-cn-ide|Exec=$out/bin/qoder-cn|g" \
        $out/share/applications/qoder-cn-ide.desktop
      sed -i "s|Exec=/usr/share/qoder-cn-ide/qoder-cn-ide|Exec=$out/bin/qoder-cn|g" \
        $out/share/applications/qoder-cn-ide-url-handler.desktop

      # Expose commandLineArgs override surface (mirrors vivaldi/vscode API).
      # wrapProgram appends the flags into argv before "$@", so the underlying
      # Electron main process receives them like a native CLI arg.
      # bubblewrap goes on PATH for Qoder's agent sandbox, which spawns the
      # system `bwrap` binary (not bundled in the deb).
      wrapProgram $out/bin/qoder-cn \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.bubblewrap ]} \
        --add-flags ${pkgs.lib.escapeShellArg commandLineArgs}

      runHook postInstall
    '';

    meta = with pkgs.lib; {
      description = "Qoder CN IDE - AI-native IDE by Alibaba";
      homepage = "https://qoder.cn";
      license = licenses.unfree;
      platforms = platforms.linux;
      mainProgram = "qoder-cn";
    };
  };
in
qoder-cn-ide
