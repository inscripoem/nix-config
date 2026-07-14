{ pkgs }:

let
  version = "3.16.5";

  src =
    if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then
      pkgs.fetchurl {
        url = "https://github.com/farion1231/cc-switch/releases/download/v${version}/CC-Switch-v${version}-Linux-x86_64.deb";
        hash = "sha256-uhyTXVbz0b9GCrphRAXLYUlyK3hcjqwmZJD76En/kJY=";
      }
    else if pkgs.stdenv.hostPlatform.system == "aarch64-linux" then
      pkgs.fetchurl {
        url = "https://github.com/farion1231/cc-switch/releases/download/v${version}/CC-Switch-v${version}-Linux-arm64.deb";
        hash = "sha256-4ZuufWSdkLfh9UaUwEL2UvsONceLv4K96sogGMAp9hY=";
      }
    else
      throw "cc-switch: unsupported system ${pkgs.stdenv.hostPlatform.system}";

  cc-switch = pkgs.stdenv.mkDerivation {
    pname = "cc-switch";
    inherit version src;

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      dpkg
      makeWrapper
      wrapGAppsHook3
    ];

    buildInputs = with pkgs; [
      glib
      gtk3
      cairo
      pango
      gdk-pixbuf
      atk
      at-spi2-core
      at-spi2-atk
      libsoup_3
      webkitgtk_4_1
      librsvg
      libayatana-appindicator
      libnotify
      openssl
      stdenv.cc.cc.lib
      libx11
      libxcb
      libxkbcommon
      wayland
    ];

    dontWrapGApps = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb --extract $src .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -r usr/* $out/

      # Strip Debian dependency-pinned wrapper paths if any and ensure exec bit
      find $out/bin -type f -exec chmod 0755 {} \; 2>/dev/null || true

      # Point the .desktop entry at the Nix store path
      if [ -f "$out/share/applications/cc-switch.desktop" ]; then
        substituteInPlace $out/share/applications/cc-switch.desktop \
          --replace-quiet "/usr/bin/cc-switch" "$out/bin/cc-switch"
      fi

      runHook postInstall
    '';

    postFixup = ''
      for bin in $out/bin/*; do
        if [ -f "$bin" ] && [ -x "$bin" ]; then
          wrapProgram "$bin" \
            "''${gappsWrapperArgs[@]}" \
            --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath [ pkgs.libayatana-appindicator ]}"
        fi
      done
    '';

    meta = with pkgs.lib; {
      description = "All-in-One desktop assistant for Claude Code, Codex, Gemini CLI, OpenCode and more (Tauri GUI)";
      homepage = "https://github.com/farion1231/cc-switch";
      license = licenses.mit;
      platforms = [ "x86_64-linux" "aarch64-linux" ];
      mainProgram = "cc-switch";
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    };
  };
in
cc-switch
