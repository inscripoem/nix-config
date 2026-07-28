{ lib, python3Packages, fetchurl }:

python3Packages.buildPythonPackage (finalAttrs: {
  pname = "ww-manager";
  version = "2.1.12";

  src = fetchurl {
    url = "https://pypi.io/packages/source/w/ww-manager/ww_manager-${finalAttrs.version}.tar.gz";
    hash = "sha256-IbhhKcWn2BhQEfKESivFeyFKYtBgo5lA6a17OPwkQjA=";
  };

  pyproject = true;

  build-system = with python3Packages; [
    hatchling
  ];

  dependencies = with python3Packages; [
    typer
    certifi
    rich
    typing-extensions
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
