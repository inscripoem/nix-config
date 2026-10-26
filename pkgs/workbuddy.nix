{
  pkgs,
  commandLineArgs ? "",
}:

let
  # Version and rev come from the official update channel:
  #   https://copilot.tencent.com/v2/update?platform=workbuddy-linux-x64-deb
  # The deb filename embeds "-<rev>"; `rev` is kept separate so
  # update-versions.sh can rewrite both fields independently.
  version = "5.6.2.40046327";
  rev = "c7b525f3";

  # nixpkgs' patchelf 0.19.x SIGABRTs while running --set-rpath on the
  # bundled python runtime binary (resources/runtime/python/bin/
  # python3.13) — same deb built fine under the 0.15 lineage, and the
  # 0.19 crash family (upstream #583/#675) is unfixed as of 0.19.2,
  # the newest release. Pin 0.15.5 (last release of the old line) for
  # this package only: autoPatchelf and the manual patchelf call below
  # both resolve `patchelf` from nativeBuildInputs' PATH.
  patchelf015 = pkgs.stdenv.mkDerivation rec {
    pname = "patchelf";
    version = "0.15.5";
    src = pkgs.fetchurl {
      url = "https://github.com/NixOS/patchelf/releases/download/${version}/patchelf-${version}.tar.gz";
      hash = "sha256-uUzTziNh+7v3uwVanZDRozh4pZQZGnxKYDcLfDIP3gg=";
    };
    # Release tarball ships a pregenerated configure script.
  };

  workbuddy = pkgs.stdenv.mkDerivation {
    pname = "workbuddy";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://download.codebuddy.cn/workbuddy/saas/linux-x64-deb/WorkBuddy-linux-x64-deb-${version}-${rev}.deb";
      hash = "sha256-EhSa2MDNdI/VBi2PYseCfWiNgJVCetqZsa6ecBmJdSM=";
    };

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      dpkg
      makeWrapper
      patchelf015
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
      mkdir -p $out/share/workbuddy

      cp -r usr/share/applications/* $out/share/applications/
      cp -r usr/share/icons/* $out/share/icons/
      # Upstream installs into /opt/WorkBuddy; flatten into share/workbuddy.
      # The bundled Electron (with app.asar beside the binary) is kept as-is,
      # so the prebuilt better-sqlite3 (electron-35 ABI) stays matched.
      cp -r opt/WorkBuddy/. $out/share/workbuddy/

      find $out -name "chrome-sandbox" -exec chmod 0755 {} \; 2>/dev/null || true
      find $out -name "workbuddy" -type f -path "*/share/workbuddy/*" -exec chmod 0755 {} \; 2>/dev/null || true

      # koffi ships ELF builds for freebsd/openbsd; autoPatchelf only skips
      # foreign *architectures*, not foreign OS ABIs, so it dies resolving
      # libc++.so.9.0 etc. Runtime variant selection is by platform/arch,
      # and this package is x86_64 glibc only — drop the BSD dirs.
      rm -rf $out/share/workbuddy/resources/app.asar.unpacked/node_modules/koffi/build/koffi/{freebsd_*,openbsd_*}

      autoPatchelf $out

      # Chromium's GPU process dlopens libGL/libEGL/libGLESv2 at runtime, so
      # autoPatchelf alone never sees them; force them into DT_NEEDED with
      # absolute store paths (same trick as nixpkgs vscode) or hardware
      # acceleration silently falls back to software rendering.
      patchelf \
        --add-needed ${pkgs.libglvnd}/lib/libGLESv2.so.2 \
        --add-needed ${pkgs.libglvnd}/lib/libGL.so.1 \
        --add-needed ${pkgs.libglvnd}/lib/libEGL.so.1 \
        $out/share/workbuddy/workbuddy

      # Create launcher script
      echo '#!/bin/sh' > $out/bin/workbuddy
      echo 'export ELECTRON_FORCE_IS_PACKAGED=1' >> $out/bin/workbuddy
      echo 'export ELECTRON_DISABLE_SANDBOX=1' >> $out/bin/workbuddy
      echo 'export DISABLE_GPU_SANDBOX=1' >> $out/bin/workbuddy
      echo "exec $out/share/workbuddy/workbuddy --no-sandbox \"\$@\"" >> $out/bin/workbuddy
      chmod +x $out/bin/workbuddy

      # Fix desktop file (upstream Exec points at /opt/WorkBuddy)
      sed -i "s|Exec=.*|Exec=$out/bin/workbuddy %U|" \
        $out/share/applications/workbuddy.desktop

      # Expose commandLineArgs override surface (mirrors vivaldi/vscode API).
      # The agent CLI sandbox looks up `bwrap` and `socat` via `which`, so both
      # go on PATH (ripgrep is vendored in the deb). Its shell PATH is closed —
      # vendored safe-bin + managed runtimes, rebuilt by the Rust sandbox-center,
      # which honors none of the CLI's env hooks (CODEBUDDY_ENV_FILE /
      # WORKBUDDY_EXTRA_PATHS) — so host tools are exposed at the shell layer
      # instead: see the zshenv append in home/packs/ai.nix (workbuddy block).
      wrapProgram $out/bin/workbuddy \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.bubblewrap pkgs.socat ]} \
        --add-flags ${pkgs.lib.escapeShellArg commandLineArgs}

      runHook postInstall
    '';

    meta = with pkgs.lib; {
      description = "WorkBuddy — AI agent desktop workspace by Tencent's CodeBuddy team";
      homepage = "https://www.workbuddy.cn";
      license = licenses.unfree;
      platforms = [ "x86_64-linux" ];
      mainProgram = "workbuddy";
    };
  };
in
workbuddy
