final: prev: {
  siyuan = final.callPackage ./siyuan.nix { };
  "trae-cn" = final.callPackage ./trae-cn.nix { };
  "cc-switch" = final.callPackage ./cc-switch.nix { };
  glances = final.callPackage ./glances.nix { originalGlances = prev.glances; };

  # Workaround: patool 4.0.5's tests fail with file 5.48 because compressed
  # tar archives without extensions are detected as the compression format
  # rather than application/x-tar. Bottles only needs patool for archives
  # that usually have proper extensions, so disabling these brittle tests is
  # low-risk. See upstream patool/file regressions (e.g. NixOS/nixpkgs#367772).
  python3Packages = prev.python3Packages.overrideScope (pyFinal: pyPrev: {
    patool = pyPrev.patool.overridePythonAttrs (old: {
      disabledTests = (old.disabledTests or [ ]) ++ [
        "test_py_tarfile_bz2"
        "test_py_tarfile_bz2_file"
        "test_tar_lzma"
        "test_tar_xz"
        "test_tar_bz2"
        "test_tar_bz2_file"
        "test_tar_lzip"
        "test_tar_xz_file"
        "test_mime_file"
        "test_mime_file_bzip"
      ];
    });
  });
}
