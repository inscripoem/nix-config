{
  appimageTools,
  lib,
  fetchurl,
}:
# Named orca-ide after upstream's own deb/rpm package name: plain `orca` is
# the GNOME screen reader in nixpkgs. Version bumps go through
# scripts/update-versions.sh --only=orca-ide; the app's built-in
# electron-updater cannot replace the read-only store AppImage, so upstream
# releases are the only update path.
let
  pname = "orca-ide";
  version = "1.4.226";

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-linux.AppImage";
    hash = "sha256-UqbZP4rO3lUAr/1uu5faba3qtre5xfVlEr/mbplC3Xo=";
  };

  appimageContents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/orca-ide.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/orca-ide.desktop \
      --replace 'Exec=AppRun %U' 'Exec=${pname} %U'
    cp -r ${appimageContents}/usr/share/icons $out/share
  '';

  meta = {
    description = "Agent Development Environment for running parallel coding agents in worktrees";
    homepage = "https://onorca.dev";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "orca-ide";
  };
}
