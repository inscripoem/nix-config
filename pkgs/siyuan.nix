{ pkgs }:

let
  version = "3.7.1";

  srcTag = pkgs.fetchFromGitHub {
    owner = "siyuan-note";
    repo = "siyuan";
    rev = "v${version}";
    hash = "sha256-K31h2noDpTn7vCXj16K2dxRPww5z+HC/nA4Gn5MAVms=";
  };

  srcDeb =
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

  siyuan-kernel = pkgs.buildGoModule {
    pname = "siyuan-kernel";
    inherit version;
    src = srcTag;
    sourceRoot = "${srcTag.name}/kernel";
    vendorHash = "sha256-fZLVqrWTWUHo6BhixB6+krXaM7WCiZpusHA8T2SicgQ=";

    ldflags = [
      "-s"
      "-w"
      "-X"
      "github.com/siyuan-note/siyuan/kernel/util.Mode=prod"
    ];
    tags = [ "fts5" ];
    doCheck = false;

    modPostBuild = ''
      chmod +w vendor/github.com/88250/gulu
      substituteInPlace vendor/github.com/88250/gulu/file.go \
        --replace-fail "os.Chmod(dest, sourceinfo.Mode())" "os.Chmod(dest, 0644)"
    '';

    postInstall = ''
      mv $out/bin/kernel $out/bin/SiYuan-Kernel
      rm -f $out/bin/harmony
    '';

    meta = with pkgs.lib; {
      description = "SiYuan kernel built from source with gulu file-mode patch";
      homepage = "https://b3log.org/siyuan/";
      license = licenses.agpl3Plus;
      platforms = [ "x86_64-linux" "aarch64-linux" ];
    };
  };

  siyuan = pkgs.stdenv.mkDerivation {
    pname = "siyuan";
    inherit version;
    src = srcDeb;

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      dpkg
      makeWrapper
      wrapGAppsHook3
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
      libxtst
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

      kernel_dest="$out/opt/SiYuan/resources/kernel/SiYuan-Kernel"
      if [ ! -f "$kernel_dest" ]; then
        echo "siyuan: expected pre-built kernel at $kernel_dest, but it is missing" >&2
        exit 1
      fi
      rm -f "$kernel_dest"
      ln -s ${siyuan-kernel}/bin/SiYuan-Kernel "$kernel_dest"

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
      sourceProvenance = with sourceTypes; [ binaryNativeCode fromSource ];
    };
  };
in
siyuan
