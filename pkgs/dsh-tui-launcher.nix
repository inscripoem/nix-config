# Official @deepseek-harness-tui/dsh-tui delegating launcher — the
# interactive dsh front end orca recognizes for agent kind "dsh"
# (detectCmd `dsh-tui`, launchCmd `dsh-tui .`). The npm package ships the
# full built TUI, but its bin is a two-role script: installed on PATH it
# is a zero-dependency thin shell (node builtins only) that delegates to
# the copy inside ~/.dsh/profiles/dsh-tui — bootstrapping that profile on
# first run via the kernel's `dsh plugin add` (which needs pnpm on PATH)
# and pinning THIS package's version at bootstrap. The rolling, /update-
# managed TUI therefore never lives in the nix closure: only the shell
# script and package.json (the shell reads it for its version identity)
# are installed here, laid out as a node_modules package so orca's
# node-package-entrypoints realpath match identifies the binary.
{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  nodejs_24,
}:
let
  pname = "dsh-tui-launcher";
  version = "0.16.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@deepseek-harness-tui/dsh-tui/-/dsh-tui-${version}.tgz";
    hash = "sha256-IUSzF9DCWuTSaI8e8sc7wsleEhCFrFl30AQH3NKxM24=";
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  sourceRoot = "package";

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    appDir="$out/lib/node_modules/@deepseek-harness-tui/dsh-tui"
    mkdir -p "$appDir/bin" "$out/bin"

    install -Dm644 package.json "$appDir/package.json"
    install -Dm755 bin/dsh-tui.js "$appDir/bin/dsh-tui.js"

    # Both upstream bin names (`dst` is orca's detectCmdAliases fallback).
    # The wrapper execs node on the store path, so the script's own
    # import.meta.url resolution still finds ../package.json.
    makeWrapper ${nodejs_24}/bin/node "$out/bin/dsh-tui" \
      --add-flags "$appDir/bin/dsh-tui.js"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/dst" \
      --add-flags "$appDir/bin/dsh-tui.js"

    runHook postInstall
  '';

  meta = {
    description = "Official dsh-tui delegating launcher (thin shell; the TUI itself lives in ~/.dsh/profiles/dsh-tui)";
    homepage = "https://github.com/ccch1mneyyy/dsh-TUI";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "dsh-tui";
  };
}
