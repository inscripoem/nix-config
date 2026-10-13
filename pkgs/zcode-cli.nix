# Official open-source ZCode CLI (TUI + Web), built from the zai-org/ZCode
# pnpm monorepo — the terminal counterpart the desktop distribution does not
# ship (its embedded glm/zcode.cjs lacks @zcode/tui). Build recipe mirrors
# AUR zcode-cli: frozen-lockfile install without lifecycle scripts (native
# deps arrive as prebuilt packages), tsc -b for the shared package, then the
# upstream build:zcode packer whose output tarball bundles runtime +
# node_modules.
{
  lib,
  stdenv,
  fetchurl,
  fetchPnpmDeps,
  nodejs_24,
  pnpm_10,
  pnpmConfigHook,
  makeWrapper,
  autoPatchelfHook,
}:
let
  pname = "zcode-cli";
  version = "3.15.1";

  src = fetchurl {
    url = "https://github.com/zai-org/ZCode/archive/refs/tags/v${version}.tar.gz";
    hash = "sha256-36sfn98NRU2Pvs6uLVRUr05Nskj3QCnjoYIbHes0MTk=";
  };

  # pnpm 10, not the nixpkgs default 12: upstream pins pnpm@10.33.2 and the
  # lockfile encodes `pnpm.overrides` from package.json, which pnpm 12 no
  # longer reads (ERR_PNPM_LOCKFILE_CONFIG_MISMATCH under --frozen-lockfile).
  pnpmDeps = fetchPnpmDeps {
    inherit version src;
    pname = "${pname}";
    pnpm = pnpm_10;
    fetcherVersion = 4;
    hash = "sha256-khnggoOSdTqsbLyCeBnXczdMxgBlNh2dEDspWRP/aRY=";
  };
in
stdenv.mkDerivation {
  inherit pname version src pnpmDeps;
  sourceRoot = "ZCode-${version}";

  nativeBuildInputs = [
    nodejs_24
    pnpm_10
    pnpmConfigHook
    makeWrapper
    autoPatchelfHook
  ];

  # Prebuilt native modules (node-pty/sharp/koffi) target glibc; give their
  # DT_NEEDED a resolvable libstdc++/libgcc. Anything exotic surfaces in the
  # autoPatchelf error list and goes into autoPatchelfIgnoreMissingDeps.
  buildInputs = [ stdenv.cc.cc.lib ];

  env = {
    HUSKY = "0";
    CI = "1";
    NODE_OPTIONS = "--max-old-space-size=8192";
  };

  # pnpmConfigHook patches only the root node_modules/.bin; workspace-local
  # .bin dirs (apps/*/packages/*/node_modules/.bin) keep #!/usr/bin/env,
  # which does not exist in the build sandbox.
  preBuild = ''
    patchShebangs --build apps packages
  '';

  buildPhase = ''
    runHook preBuild
    pnpm exec tsc -b packages/shared
    pnpm --filter "@zcode/cli..." build
    pnpm --filter "@zcode/server..." build
    pnpm --filter "@zcode/web..." build
    pnpm build:zcode --skip-build \
      --base-url "https://github.com/zai-org/ZCode/releases/download/v${version}/" \
      --out-dir dist/zcode
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    tar -xzf dist/zcode/releases/${version}/zcode-${version}.tar.gz -C $out/lib
    makeWrapper ${nodejs_24}/bin/node $out/bin/zcode \
      --add-flags $out/lib/zcode/bin/zcode.mjs
    runHook postInstall
  '';

  meta = {
    description = "Official ZCode CLI (TUI + Web) built from source";
    homepage = "https://github.com/zai-org/ZCode";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "zcode";
  };
}
