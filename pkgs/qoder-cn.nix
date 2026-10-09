{ pkgs, commandLineArgs ? "" }:

let
  version = "0.4.3";

  qoder-cn = pkgs.stdenv.mkDerivation {
    pname = "qoder-cn";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://qoder-app.oss-cn-beijing.aliyuncs.com/qoder-app/releases/${version}/Qoder-CN-linux-amd64.deb";
      hash = "sha256-MwfndQ8kmR0unxvnlrtGZr52B/fY2COs6MAQPF+efvk=";
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
      mkdir -p $out/share/icons
      mkdir -p $out/share/qoder-cn

      cp -r usr/share/applications/* $out/share/applications/
      cp -r usr/share/icons/* $out/share/icons/
      # Upstream installs into "opt/Qoder CN" (productName, contains a
      # space); flatten into share/qoder-cn.
      cp -r "opt/Qoder CN"/. $out/share/qoder-cn/

      find $out -name "chrome-sandbox" -exec chmod 0755 {} \; 2>/dev/null || true
      find $out -name "qoder-cn" -type f -exec chmod 0755 {} \; 2>/dev/null || true

      autoPatchelf $out

      # Chromium's GPU process dlopens libGL/libEGL/libGLESv2 at runtime, so
      # autoPatchelf alone never sees them; force them into DT_NEEDED with
      # absolute store paths (same trick as nixpkgs vscode) or hardware
      # acceleration silently falls back to software rendering.
      patchelf \
        --add-needed ${pkgs.libglvnd}/lib/libGLESv2.so.2 \
        --add-needed ${pkgs.libglvnd}/lib/libGL.so.1 \
        --add-needed ${pkgs.libglvnd}/lib/libEGL.so.1 \
        $out/share/qoder-cn/qoder-cn

      # Create launcher script
      if [ -f "$out/share/qoder-cn/qoder-cn" ]; then
        echo '#!/bin/sh' > $out/bin/qoder-cn
        echo 'export ELECTRON_FORCE_IS_PACKAGED=1' >> $out/bin/qoder-cn
        echo 'export ELECTRON_DISABLE_SANDBOX=1' >> $out/bin/qoder-cn
        echo 'export DISABLE_GPU_SANDBOX=1' >> $out/bin/qoder-cn
        echo "exec $out/share/qoder-cn/qoder-cn --no-sandbox \"\$@\"" >> $out/bin/qoder-cn
        chmod +x $out/bin/qoder-cn
      fi

      # Fix desktop file (upstream Exec points at the quoted spacey path)
      sed -i "s|Exec=.*|Exec=$out/bin/qoder-cn %U|" \
        $out/share/applications/qoder-cn.desktop

      # Expose commandLineArgs override surface (mirrors vivaldi/vscode API).
      # wrapProgram appends the flags into argv before "$@", so the underlying
      # Electron main process receives them like a native CLI arg.
      # bubblewrap goes on PATH for the agent sandbox, which spawns the
      # system `bwrap` binary (not bundled in the deb).
      wrapProgram $out/bin/qoder-cn \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.bubblewrap ]} \
        --add-flags ${pkgs.lib.escapeShellArg commandLineArgs}

      runHook postInstall
    '';

    meta = with pkgs.lib; {
      description = "Qoder CN - agentic coding desktop app by Alibaba (new-form, not the IDE)";
      homepage = "https://qoder.cn";
      license = licenses.unfree;
      platforms = platforms.linux;
      mainProgram = "qoder-cn";
    };
  };
in
qoder-cn
