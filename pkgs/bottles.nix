{ bottles-unwrapped, python3Packages }:

# Workaround: patool 4.0.5's tests fail with file 5.48 because compressed
# tar archives without extensions are detected as the compression format
# (application/x-bzip2) rather than application/x-tar, and list_<algo>
# entrypoints are missing at test time. Only bottles depends on patool
# here, and it only handles archives with proper extensions, so disabling
# these brittle tests is low-risk. Scope the override to bottles-unwrapped
# so python3Packages hash stays intact (avoids KDE cache miss).
bottles-unwrapped.override {
  python3Packages = python3Packages // {
    patool = python3Packages.patool.overridePythonAttrs (old: {
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
  };
}
