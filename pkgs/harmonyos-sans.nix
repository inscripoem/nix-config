{ stdenvNoCC, fetchurl, unzip, lib }:

stdenvNoCC.mkDerivation {
  pname = "harmonyos-sans";
  version = "2023-02-26";

  src = fetchurl {
    url = "https://media.githubusercontent.com/media/huawei-fonts/HarmonyOS-Sans/33ab3b81b92c01f5e340c89960872bee174d8704/HarmonyOS%20Sans.zip";
    hash = "sha256-gG5ouMrQaEjWDachFRnHtwqBWIzcGc7A1yOAV6BybT4=";
  };

  nativeBuildInputs = [ unzip ];

  unpackPhase = ''
    unzip "$src"
  '';

  installPhase = ''
    mkdir -p "$out/share/fonts/truetype/harmonyos-sans"
    cp "HarmonyOS Sans/HarmonyOS_Sans_SC"/*.ttf "$out/share/fonts/truetype/harmonyos-sans/"
  '';

  meta = with lib; {
    description = "HarmonyOS Sans SC Chinese fonts (static weights only)";
    homepage = "https://developer.harmonyos.com/cn/docs/design/des-guides/font-0000001157868583";
    license = licenses.unfreeRedistributable;
    platforms = platforms.linux;
  };
}
