{ pkgs, ... }:

let
  version = "3.7.1";

  src =
    if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then
      pkgs.fetchurl {
        url = "https://github.com/siyuan-note/siyuan/releases/download/v${version}/siyuan-${version}-linux.deb";
        hash = "sha256-/4rXnhgjT78H9i/DtLCzSLOak368jlLzfzd2rQ2u538=";
      }
    else if pkgs.stdenv.hostPlatform.system == "aarch64-linux" then
      pkgs.fetchurl {
        url = "https://github.com/siyuan-note/siyuan/releases/download/v${version}/siyuan-${version}-linux-arm64.deb";
        hash = "sha256-FUF2CUAt3JfGzS5ZkCBTYRcuIZnC80Xjdg/UjMHIk3M=";
      }
    else
      throw "siyuan: unsupported system ${pkgs.stdenv.hostPlatform.system}";

  siyuan = pkgs.stdenv.mkDerivation {
    pname = "siyuan";
    inherit version src;

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      dpkg
      makeWrapper
      wrapGAppsHook3
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc.lib
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
      xorg.libxcb
      xorg.libxkbfile
      xorg.libXinerama
      xorg.libXcursor
      xorg.libXi
      xorg.libXScrnSaver
      xorg.libXtst
      libdrm
      mesa
      nss
      nspr
      cups
      dbus
      libgcrypt
      libsecret
      gtk3
      pango
      cairo
      atk
      glib
      expat
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
      at-spi2-atk
    ];

    dontWrapGApps = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb --extract $src .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/share
      cp -r opt $out/
      cp -r usr/share/applications $out/share/ 2>/dev/null || true
      cp -r usr/share/icons $out/share/ 2>/dev/null || true

      find $out/opt -name "chrome-sandbox" -exec chmod 0755 {} \; 2>/dev/null || true

      runHook postInstall
    '';

    postFixup = ''
      siyuan_bin="$(find $out/opt -maxdepth 3 -name siyuan -type f -executable | head -1)"
      if [ -z "$siyuan_bin" ]; then
        echo "siyuan: could not locate main binary under $out/opt" >&2
        exit 1
      fi

      makeWrapper "$siyuan_bin" $out/bin/siyuan \
        "''${gappsWrapperArgs[@]}" \
        --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath [ pkgs.libappindicator-gtk3 pkgs.libnotify ]}"

      for desktop in $out/share/applications/*.desktop; do
        [ -f "$desktop" ] || continue
        substituteInPlace "$desktop" \
          --replace-quiet "/opt/SiYuan/siyuan" "$out/bin/siyuan" \
          --replace-quiet "/opt/SiYuan/" "$out/bin/"
      done
    '';

    meta = with pkgs.lib; {
      description = "Refactor your thinking - a privacy-first personal knowledge management system";
      homepage = "https://b3log.org/siyuan/";
      license = licenses.agpl3Plus;
      platforms = [ "x86_64-linux" "aarch64-linux" ];
      mainProgram = "siyuan";
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    };
  };
in
{
  home.packages = [ siyuan ];
}
