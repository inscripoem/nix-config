# Hermes — Apollo-derived Linux game-streaming host (MrOz59/Hermes), packaged
# as the Phase 1 deliverable of the Sunshine migration (plan 2026-11-10; see
# modules/nixos/capabilities/hermes.nix and docs/remote-desktop.md).
#
# Derivation modeled on nixpkgs' sunshine package (same upstream cmake
# lineage): separate buildNpmPackage for the Vue/vite web UI, vendored static
# ffmpeg from the third-party/build-deps submodule (FFMPEG_PREPARED_BINARIES
# defaults to the in-tree dist snapshot — no network fetch to redirect),
# system boost instead of FetchContent, and the NPM custom target removed so
# plain `cmake --build` (ALL) can build everything else.
#
# Deliberately omitted:
#   - PyroWave (Vulkan AV1 encoder): optional upstream (pkg-config, QUIET),
#     requires pinning pyrowave + Granite + volk + vulkan-headers fetches;
#     Polaris VCE 3.4 has no AV1 encode, so nothing on briefcase can use it.
#     Add a pkgs/hermes/pyrowave.nix + PKG_CONFIG_PATH if that changes.
#   - CUDA: -DSUNSHINE_ENABLE_CUDA=off, no NVIDIA hardware on any host.
#
# Update mechanism: `scripts/update-versions.sh --only=hermes` bumps `version`
# and resolves src.hash / ui.npmDepsHash by building `.#hermes.src` and
# `.#hermes.ui` with placeholder hashes and parsing the `got:` line of the
# fetch errors (nix-prefetch-git, which could prefetch submodule trees, is not
# installed on this host).
{
  lib,
  stdenv,
  fetchFromGitHub,
  applyPatches,
  buildNpmPackage,
  autoPatchelfHook,
  makeWrapper,
  cmake,
  pkg-config,
  acl,
  wayland-scanner,
  shaderc,
  boost,
  curl,
  miniupnpc,
  nlohmann_json,
  openssl,
  libopus,
  qt6,
  avahi,
  libevdev,
  libpulseaudio,
  libx11,
  libxcb,
  libxfixes,
  libxrandr,
  libxi,
  libxtst,
  libdrm,
  wayland,
  libffi,
  libcap,
  libgbm,
  pcre2,
  libuuid,
  libselinux,
  libsepol,
  libthai,
  libdatrie,
  libxkbcommon,
  libepoxy,
  libva,
  libvdpau,
  numactl,
  vulkan-loader,
  vulkan-headers,
  plasma-wayland-protocols,
  pipewire,
  libnotify,
  libglvnd,
  coreutils,
  udevCheckHook,
}:
let
  inherit (stdenv.hostPlatform) isLinux;
  version = "0.7.0";

  # The Linux input backend is a mandatory FetchContent of this fork. The
  # sandbox has no network, so pin it here and hand cmake the local tree via
  # FETCHCONTENT_SOURCE_DIR_HERMES_LIBVIRTUALHID (fetch commit mirrors
  # cmake/compile_definitions/linux.cmake).
  libvirtualhid = fetchFromGitHub {
    owner = "MrOz59";
    repo = "libvirtualhid";
    rev = "14ee6c4717d32b678c2983bfa6c54019b944d421";
    hash = "sha256-Z/epYF+df2bSDKwJ489eyJijPk9Ea2yMffryNUyLKVU=";
  };

  gitSrc = fetchFromGitHub {
    owner = "MrOz59";
    repo = "Hermes";
    tag = "v${version}";
    # third-party/* submodules carry the vendored static ffmpeg (build-deps
    # dist snapshot), moonlight-common-c (with nested enet), wayland-protocols
    # and the pre-generated glad sources.
    hash = "sha256-2085A4cYQDfdrqD4IQe3BuNEjQG/6f9ztant7/sJfrw=";
    fetchSubmodules = true;
  };

  # Upstream ships no npm lockfile (Arch resolves online at build time); drop
  # the vendored lock in so fetchNpmDeps can pin the web UI deps. Regenerate
  # with `nix shell nixpkgs#nodejs -c npm install --package-lock-only
  # --ignore-scripts` against the new package.json — the hermes section of
  # scripts/update-versions.sh does this on bump.
  src = applyPatches {
    src = gitSrc;
    name = "hermes-${version}-source";
    postPatch = ''
      install -Dm644 ${./package-lock.json} package-lock.json
    '';
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "hermes";
  inherit version;

  __structuredAttrs = true;
  strictDeps = true;

  inherit src;

  ui = buildNpmPackage {
    inherit (finalAttrs) src version;
    pname = "hermes-ui";
    npmDepsHash = "sha256-Y+PNO/BMZzHRlhvufpPC2updMxveoTDhiBwTRQAF5dE=";

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -a . "$out"/

      runHook postInstall
    '';
  };

  postPatch = ''
    # The web UI is built separately (see ui); drop the npm custom target so
    # `cmake --build` (ALL) does not try to run npm, and the npm lookup with it.
    substituteInPlace cmake/targets/common.cmake \
      --replace-fail 'find_program(NPM npm REQUIRED)' ""
    sed -i '/add_custom_target(web-ui ALL/,/^        VERBATIM)/d' cmake/targets/common.cmake
  ''
  # use system boost instead of FetchContent.
  # FETCH_CONTENT_BOOST_USED prevents Simple-Web-Server from re-finding boost
  + ''
    sed -i -E 's/set\(BOOST_VERSION "[^"]*"\)/set(BOOST_VERSION "${boost.version}")/' \
      cmake/dependencies/Boost_Sunshine.cmake
    echo 'set(FETCH_CONTENT_BOOST_USED TRUE)' >> cmake/dependencies/Boost_Sunshine.cmake
  ''
  # remove upstream dependency on systemd and udev for install-path discovery
  # (the paths are pinned via cmakeFlags below)
  + lib.optionalString isLinux ''
    substituteInPlace cmake/packaging/linux.cmake \
      --replace-fail 'find_package(Systemd)' "" \
      --replace-fail 'find_package(Udev)' ""
  '';

  nativeBuildInputs = [
    cmake
    pkg-config
    makeWrapper
    qt6.wrapQtAppsHook
  ]
  ++ lib.optionals isLinux [
    wayland-scanner
    shaderc # provides glslc, needed at configure time for shader compilation
    # the vendored ffmpeg ships prebuilt .a archives from build-deps
    autoPatchelfHook
  ];

  buildInputs = [
    boost
    curl
    miniupnpc
    nlohmann_json
    openssl
    libopus
    qt6.qtbase
    qt6.qtsvg
  ]
  ++ lib.optionals isLinux [
    acl # sys/acl.h — card-broker / render-node ACL work
    avahi
    libevdev
    libpulseaudio
    libx11
    libxcb
    libxfixes
    libxrandr
    libxi
    libxtst
    libdrm
    wayland
    libffi
    libcap
    libgbm
    pcre2
    libuuid
    libselinux
    libsepol
    libthai
    libdatrie
    libxkbcommon
    libepoxy
    libva
    libvdpau
    numactl
    vulkan-loader
    vulkan-headers
    plasma-wayland-protocols
    pipewire
    libnotify
  ];

  runtimeDependencies = lib.optionals isLinux [
    avahi
    libgbm
    libxrandr
    libxcb
    libglvnd
  ];

  cmakeFlags = [
    "-Wno-dev"
    (lib.cmakeBool "BOOST_USE_STATIC" false)
    (lib.cmakeBool "SUNSHINE_ENABLE_CUDA" false)
    # binary is renamed sunshine -> hermes in postInstall (upstream PKGBUILD
    # does the same rename); the generated systemd unit points here.
    (lib.cmakeFeature "SUNSHINE_EXECUTABLE_PATH" "${placeholder "out"}/bin/hermes")
    (lib.cmakeFeature "SUNSHINE_ASSETS_DIR" "share/hermes")
    # upstream tries to use systemd and udev packages to find these directories
    # in FHS; set the paths explicitly instead
    (lib.cmakeBool "UDEV_FOUND" true)
    (lib.cmakeBool "SYSTEMD_FOUND" true)
    (lib.cmakeFeature "UDEV_RULES_INSTALL_DIR" "lib/udev/rules.d")
    (lib.cmakeFeature "SYSTEMD_USER_UNIT_INSTALL_DIR" "lib/systemd/user")
    (lib.cmakeFeature "SYSTEMD_SYSTEM_UNIT_INSTALL_DIR" "lib/systemd/system")
    (lib.cmakeFeature "SYSTEMD_MODULES_LOAD_DIR" "lib/modules-load.d")
    # feed the mandatory libvirtualhid FetchContent from the pinned local tree
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_HERMES_LIBVIRTUALHID" "${libvirtualhid}")
  ];

  env = {
    BUILD_VERSION = finalAttrs.version;
    BRANCH = "main";
    COMMIT = gitSrc.rev;
  };

  # copy webui where cmake's install rule picks it up
  # (${CMAKE_BINARY_DIR}/assets/web — vite writes there when
  # SUNSHINE_ASSETS_DIR points at the cmake binary dir; the nixpkgs sunshine
  # package uses the same copy-into-existing-dir merge)
  preBuild = ''
    cp -r ${finalAttrs.ui}/build ../
  '';

  installPhase = ''
    runHook preInstall

    cmake --install .

    # mirror upstream's Arch package: cmake's VERSION property installs the
    # real binary as sunshine-<ver> with an unversioned symlink; the real one
    # becomes `hermes` and the symlink goes away. The generated user unit
    # keeps its Sunshine-lineage name until renamed here as well.
    rm -f "$out/bin/sunshine"
    mv "$out/bin/sunshine-"* "$out/bin/hermes"
    if [ -f "$out/lib/systemd/user/sunshine.service" ]; then
      mv "$out/lib/systemd/user/sunshine.service" "$out/lib/systemd/user/hermes.service"
    fi

    # The session-input udev rule calls its broker by the upstream FHS path
    # (/usr/bin/hermes-session-broker); NixOS' udev-rules builder runs an
    # absolute-path existence check over every wired rules file and fails
    # the whole system build on a dangling /usr/bin reference. The broker
    # ships in this package, so point the rule at its own bin/ — rule and
    # binary then share one closure (both TEST== and RUN+ carry the path).
    substituteInPlace "$out/lib/udev/rules.d/99-hermes-session-input.rules" \
      --replace-fail '/usr/bin/hermes-session-broker' "$out/bin/hermes-session-broker"

    runHook postInstall
  '';

  dontWrapQtApps = true;

  postFixup = ''
    wrapProgram "$out/bin/hermes" "''${qtWrapperArgs[@]}"
  '';

  doInstallCheck = isLinux;

  nativeInstallCheckInputs = lib.optionals isLinux [ udevCheckHook ];

  passthru = {
    inherit (finalAttrs) ui;
  };

  meta = {
    description = "Apollo-derived Linux game-streaming host with virtual display support, for Moonlight/Artemis/Hestia";
    homepage = "https://github.com/MrOz59/Hermes";
    changelog = "https://github.com/MrOz59/Hermes/blob/main/CHANGELOG.md";
    license = lib.licenses.gpl3Only;
    mainProgram = "hermes";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
