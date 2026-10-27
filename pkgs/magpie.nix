{
  lib,
  stdenv,
  fetchurl,
  wrapGAppsHook3,
  glib,
  gtk3,
  gdk-pixbuf,
  pango,
  cairo,
  atk,
  webkitgtk_4_1,
  libsoup_3,
  wayland,
  libx11,
  fontconfig,
}:

let
  version = "0.1.1734";

  # Upstream ships two Linux artifacts per release: the GUI build (this one,
  # dynamically linked against GTK 3 + WebKitGTK 4.1) and a static CLI build.
  # The GUI binary carries the full CLI surface too (magpie ls/tui/web ...),
  # so one artifact serves both.
  src =
    {
      "x86_64-linux" = fetchurl {
        url = "https://github.com/yetone/magpie-releases/releases/download/v${version}/magpie-linux-amd64";
        hash = "sha256-1sSCqtD9x7/bEPEABNuSPln+K2/gvOieIenNUkNfZeo=";
      };
      "aarch64-linux" = fetchurl {
        url = "https://github.com/yetone/magpie-releases/releases/download/v${version}/magpie-linux-arm64";
        hash = "sha256-GydSelaFcNFrnEnYWO6ABbw4mhWs/Hsop4BCcQ6iugg=";
      };
    }
    .${stdenv.hostPlatform.system} or (throw "magpie: unsupported system ${stdenv.hostPlatform.system}");

  # Same icon upstream's install.sh drops into the hicolor theme.
  icon = fetchurl {
    url = "https://usemagpie.ai/img/icon-256.png";
    hash = "sha256-V0N8ZZbgWo/PxC1CiMAwqgDthraf411GTWnXAmFQxwQ=";
  };

  libs = [
    glib
    gtk3
    gdk-pixbuf
    pango
    cairo
    atk
    webkitgtk_4_1
    libsoup_3
    wayland
    libx11
    fontconfig
  ];
in
stdenv.mkDerivation {
  pname = "magpie";
  inherit version src;

  # The binary ships untouched. patchelf (via autoPatchelfHook) rewriting the
  # interpreter/RUNPATH of this Go/CGO ELF segfaults ld.so's dl_main before
  # any code runs (glibc 2.44, zero output, exit 139); the untouched binary
  # works fine against the same loader with the libs on LD_LIBRARY_PATH
  # (verified 2026-10-27). NixOS provides /lib64/ld-linux-x86-64.so.2 from
  # the system glibc, which is the same 2.44 the closure pins.
  nativeBuildInputs = [
    wrapGAppsHook3
  ];

  buildInputs = libs;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  # Libraries ride LD_LIBRARY_PATH instead of an ELF RPATH (see above), added
  # into wrapGAppsHook3's wrapper along with its usual GIO/pixbuf/schema env.
  preFixup = ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath libs}
    )
  '';

  installPhase = ''
    runHook preInstall

    install -Dm0755 $src $out/bin/magpie
    install -Dm0644 ${icon} $out/share/icons/hicolor/256x256/apps/magpie.png

    # Same entry upstream's install.sh generates; Exec is store-pathed and
    # the magpie:// scheme (import links) is registered by the MimeType line.
    mkdir -p $out/share/applications
    cat > $out/share/applications/magpie.desktop <<EOF
[Desktop Entry]
Type=Application
Name=magpie
Comment=Every agent's model. One place.
Exec=$out/bin/magpie %u
Icon=magpie
StartupWMClass=magpie
Categories=Development;Utility;
MimeType=x-scheme-handler/magpie;
Terminal=false
EOF

    runHook postInstall
  '';

  meta = {
    description = "Model and provider manager for AI coding agents, with a local API gateway";
    homepage = "https://usemagpie.ai";
    changelog = "https://github.com/yetone/magpie-releases/releases/tag/v${version}";
    license = lib.licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "magpie";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
