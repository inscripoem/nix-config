{
  lib,
  python3Packages,
}:
# Google's official Colab CLI (PyPI project google-colab-cli): provision
# Colab CPU/GPU/TPU runtimes and drive them from the terminal; the entrypoint
# is `colab`. Version bumps go through scripts/update-versions.sh
# --only=colab-cli, which also tracks the two dependencies missing from
# nixpkgs (built below from their PyPI wheels, both pure Python):
#   - jupyter-kernel-client, pinned with == by colab-cli's own metadata
#   - jupyter-mimetypes, an unpinned dependency of jupyter-kernel-client
let
  colabCliVersion = "0.7.4";
  colabCliHash = "sha256-FDXzUzpwZPJ7i4ElLahTcEJ9bPk7lObDRze9HMaOwpI=";

  jkcVersion = "0.9.0";
  jkcHash = "sha256-d6y48vc42XYl1r0B7ozyHE1ZeQt7pGQQhxLbOHBBbyA=";

  jmtVersion = "0.2.0";
  jmtHash = "sha256-5tzZiSWOP8lENltlbZFzGRUX4OOTvYeOl85QDls4hSc=";

  jupyter-mimetypes = python3Packages.buildPythonPackage {
    pname = "jupyter-mimetypes";
    version = jmtVersion;
    format = "wheel";

    src = python3Packages.fetchPypi {
      pname = "jupyter_mimetypes";
      version = jmtVersion;
      format = "wheel";
      python = "py3";
      dist = "py3";
      hash = jmtHash;
    };

    dependencies = with python3Packages; [
      pyarrow
      typing-extensions
    ];

    meta = {
      description = "Mimetypes for Jupyter data";
      homepage = "https://github.com/datalayer/jupyter-mimetypes";
      license = lib.licenses.bsd3;
    };
  };

  jupyter-kernel-client = python3Packages.buildPythonPackage {
    pname = "jupyter-kernel-client";
    version = jkcVersion;
    format = "wheel";

    src = python3Packages.fetchPypi {
      pname = "jupyter_kernel_client";
      version = jkcVersion;
      format = "wheel";
      python = "py3";
      dist = "py3";
      hash = jkcHash;
    };

    dependencies = with python3Packages; [
      jupyter-client
      jupyter-core
      jupyter-mimetypes
      requests
      traitlets
      typing-extensions
      websocket-client
    ];

    meta = {
      description = "Python client for Jupyter kernels";
      homepage = "https://github.com/datalayer/jupyter-kernel-client";
      license = lib.licenses.bsd3;
    };
  };
in
python3Packages.buildPythonApplication {
  pname = "colab-cli";
  version = colabCliVersion;
  format = "wheel";

  src = python3Packages.fetchPypi {
    pname = "google_colab_cli";
    version = colabCliVersion;
    format = "wheel";
    python = "py3";
    dist = "py3";
    hash = colabCliHash;
  };

  dependencies =
    with python3Packages;
    [
      click
      filelock
      google-auth
      google-auth-oauthlib
      html2text
      nbformat
      packaging
      prompt-toolkit
      pydantic
      pygments
      requests
      rich
      typer
      typing-extensions
      websocket-client
    ]
    ++ [ jupyter-kernel-client ];

  pythonImportsCheck = [ "colab_cli" ];

  meta = {
    description = "CLI for interacting with Google Colab runtimes";
    homepage = "https://github.com/googlecolab/google-colab-cli";
    changelog = "https://github.com/googlecolab/google-colab-cli/blob/main/CHANGELOG.md";
    license = lib.licenses.asl20;
    mainProgram = "colab";
  };
}
