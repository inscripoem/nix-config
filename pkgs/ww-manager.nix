{ lib, python3Packages, fetchurl }:

python3Packages.buildPythonPackage (finalAttrs: {
  pname = "ww-manager";
  version = "2.3.2";

  src = fetchurl {
    url = "https://pypi.io/packages/source/w/ww-manager/ww_manager-${finalAttrs.version}.tar.gz";
    hash = "sha256-o3YWaf3gZZaEAgZT+dMevXTZfAwGXXk9TutdbWUguRs=";
  };

  pyproject = true;

  build-system = with python3Packages; [
    hatchling
  ];

  dependencies = with python3Packages; [
    typer
    certifi
    requests
    rich
    typing-extensions
    prompt-toolkit
  ];

  pythonImportsCheck = [
    "ww_manager"
  ];

  meta = with lib; {
    description = "Wuthering Waves CLI manager";
    homepage = "https://pypi.org/project/ww-manager/";
    license = licenses.mit;
    maintainers = [];
    platforms = platforms.unix;
  };
})
