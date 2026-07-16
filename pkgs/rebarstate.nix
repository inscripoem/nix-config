{ pkgs }:

let
  version = "0.3";

  src = pkgs.fetchFromGitHub {
    owner = "xCuri0";
    repo = "ReBarUEFI";
    rev = version;
    hash = "sha256-Ikfd2+/NNuZf9TRTFlSM3mzWa/9uWr32RU1Zld+5tFE=";
  };

  rebarstate = pkgs.stdenv.mkDerivation {
    pname = "rebarstate";
    inherit version src;

    nativeBuildInputs = [ pkgs.cmake ];

    postPatch = ''
      # 0.3 is missing the <cstdint> header required by newer GCC.
      sed -i '/^#include <cmath>/a #include <cstdint>' ReBarState/ReBarState.cpp
    '';

    preConfigure = ''
      cd ReBarState
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 ReBarState $out/bin/rebarstate
      runHook postInstall
    '';

    meta = with pkgs.lib; {
      description = "UEFI variable utility to configure ReBarUEFI resizable BAR state";
      homepage = "https://github.com/xCuri0/ReBarUEFI";
      license = licenses.mit;
      platforms = [ "x86_64-linux" ];
      mainProgram = "rebarstate";
    };
  };
in
rebarstate
