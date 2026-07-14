{ pkgs, lib, stdenv, fetchFromGitHub, hddtemp, podman, python3Packages, which, makeWrapper }:

# Glances 4.5.5 with NixOS-specific GPU monitoring fixes.
#
# Upstream 4.5.5 ships a GPU plugin that supports NVIDIA, AMD, Intel and ARM.
# The Intel plugin reads /sys/class/drm and works on Arc A380 out of the box.
#
# For NVIDIA we still need two extra fixes:
#   1. Inject nvidia-ml-py into PYTHONPATH (the stock derivation omits it).
#   2. Append /run/opengl-driver/lib to LD_LIBRARY_PATH so NVML can load
#      libnvidia-ml.so.1 on NixOS.
#
# The LD_LIBRARY_PATH suffix is harmless on hosts without an NVIDIA card:
# on Intel Arc the directory holds mesa libs, which glances ignores.

let
  glancesUnwrapped = python3Packages.buildPythonApplication (finalAttrs: {
    pname = "glances";
    version = "4.5.5";
    pyproject = true;

    disabled = python3Packages.isPyPy;

    src = fetchFromGitHub {
      owner = "nicolargo";
      repo = "glances";
      tag = "v${finalAttrs.version}";
      hash = "sha256-RiAt797YS468lmwH68O9/KlbV46DAqd25O8J0wNIDsU=";
    };

    build-system = with python3Packages; [ setuptools ];

    # On Darwin this package segfaults due to mismatch of pure and impure
    # CoreFoundation. This issues was solved for binaries but for interpreted
    # scripts a workaround below is still required.
    # Relevant: https://github.com/NixOS/nixpkgs/issues/24693
    makeWrapperArgs = lib.optionals stdenv.hostPlatform.isDarwin [
      "--set"
      "DYLD_FRAMEWORK_PATH"
      "/System/Library/Frameworks"
    ];

    # some tests fail in darwin sandbox
    doCheck = !stdenv.hostPlatform.isDarwin;

    dependencies =
      with python3Packages;
      [
        defusedxml
        packaging
        psutil
        pyinstrument
        pysnmp
        fastapi
        uvicorn
        requests
        jinja2
        python-jose
        prometheus-client
        shtab
        nvidia-ml-py
      ]
      ++ [ which ]
      ++ lib.optionals stdenv.hostPlatform.isLinux [ hddtemp ];

    nativeCheckInputs =
      with python3Packages;
      [
        chevron
        pytestCheckHook
        selenium
      ]
      ++ [
        podman
        which
      ];

    disabledTestPaths = [
      # Message: Unable to obtain driver for chrome
      "tests/test_webui.py"
    ];

    disabledTests = [
      # Upstream bug: diskio plugin doesn't check if args is None before accessing attributes
      # Bug report: https://github.com/nicolargo/glances/issues/3429
      "test_msg_curse_returns_list"
      "test_msg_curse_with_max_width"
      # Network test expects visible network interfaces
      # Default config hides loopback and interfaces without IP (glances.conf)
      # In Nix sandbox environment, this results in zero visible interfaces
      "test_glances_api_plugin_network"
      # Test always returns 3 plugin updates, but needs >=5 to not fail
      # May be an upstream bug, see: https://github.com/nicolargo/glances/issues/3430
      "test_perf_update"
      # Upstream pipe handling currently fails under the new 4.5.2 sanitization coverage
      "test_pipe"
    ];

    meta = {
      homepage = "https://nicolargo.github.io/glances/";
      description = "Cross-platform curses-based monitoring tool";
      mainProgram = "glances";
      changelog = "https://github.com/nicolargo/glances/blob/${finalAttrs.src.tag}/NEWS.rst";
      license = lib.licenses.lgpl3Only;
      maintainers = with lib.maintainers; [ koral ];
    };
  });

  glancesWrapped = pkgs.symlinkJoin {
    name = "glances-${glancesUnwrapped.version}";
    paths = [ glancesUnwrapped ];
    nativeBuildInputs = [ makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/glances \
        --suffix LD_LIBRARY_PATH : /run/opengl-driver/lib
    '';
    inherit (glancesUnwrapped) meta;
  };
in
glancesWrapped
