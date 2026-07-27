{ lib, python3Packages, fetchurl }:

python3Packages.buildPythonPackage (finalAttrs: {
  pname = "ww-manager";
  version = "2.1.12";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/1c/7a/eaf007e8648f535b75bb98abd5c5547ed116b2e2a8299c99d375b02681ee/ww_manager-${finalAttrs.version}.tar.gz";
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
