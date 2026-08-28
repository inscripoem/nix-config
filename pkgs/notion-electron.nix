{
  appimageTools,
  lib,
  fetchurl,
}:
let
  pname = "notion-electron";
  version = "2.4.0";

  src = fetchurl {
    url = "https://github.com/anechunaev/notion-electron/releases/download/v${version}/Notion_Electron-${version}-x86_64.AppImage";
    hash = "sha256-jpEQb4k7nWGefzspAPppxisJMlmBNUxRwSfHsylaQKY=";
  };

  appimageContents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/notion-electron.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/notion-electron.desktop \
      --replace 'Name=Notion Electron' 'Name=Notion' \
      --replace 'Exec=AppRun --no-sandbox %U' 'Exec=${pname} %U'
    cp -r ${appimageContents}/usr/share/icons $out/share
  '';

  meta = {
    description = "Unofficial Notion desktop client for Linux, built with modern Electron";
    homepage = "https://github.com/anechunaev/notion-electron";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "notion-electron";
  };
}
