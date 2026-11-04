# Minimal dsh bundle for Orca's Claude Code hook bridge.
#
# Orca writes a global ~/.dsh/cordis.patch.yml entry that inserts
# @deepseek-ai/dsh-hooks-claude-code into every profile. The frozen TUI
# preset's managed profile (nix-tui) has no profile-level node_modules, so
# the bridge must live in the composed tree. This bundle supplies exactly
# the two npm packages the bridge needs, links the kernel's node_modules
# into each for peer resolution, and ships an empty Cordis patch — Orca's
# home-level patch does the actual insertion.
#
# Upstream marks the bridge experimental (packages/experimental/
# hooks-claude-code). Its peer versions are tied to the kernel, so version
# equals the pinned kernel version. Update track: update-versions.sh
# --only=dsh-orca-hooks resolves the kernel from flake.lock and bumps
# `version`, `hooksHash` and `protocolHash` together.
{
  lib,
  stdenvNoCC,
  fetchurl,
  dsh-kernel,
}:
let
  version = "0.2.2-alpha.3";
  hooksHash = "sha256-qAiAPWKAYrwl5atNCqaO534kS1iNXpIyA6SUP61Jn5E=";
  protocolHash = "sha256-5AhH/24UdrIDpCxOHt1HkzxNJmXgGnsQc47eZ/MsMN8=";

  hooksSrc = fetchurl {
    url = "https://registry.npmjs.org/@deepseek-ai/dsh-hooks-claude-code/-/dsh-hooks-claude-code-${version}.tgz";
    hash = hooksHash;
  };
  protocolSrc = fetchurl {
    url = "https://registry.npmjs.org/@deepseek-ai/dsh-hook-protocol/-/dsh-hook-protocol-${version}.tgz";
    hash = protocolHash;
  };

  kernelNodeModules = "${dsh-kernel}/lib/deepseek-harness/node_modules";
in
stdenvNoCC.mkDerivation {
  pname = "dsh-orca-hooks";
  inherit version;

  src = null;
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  strictDeps = true;

  installPhase = ''
    runHook preInstall

    nm="$out/lib/node_modules"
    mkdir -p "$nm/@deepseek-ai" "$nm/dsh-orca-hooks" "$out/nix-support"

    for pkg in dsh-hooks-claude-code dsh-hook-protocol; do
      mkdir -p "$nm/@deepseek-ai/$pkg"
    done
    tar -xzf ${hooksSrc} --strip-components=1 \
      -C "$nm/@deepseek-ai/dsh-hooks-claude-code"
    tar -xzf ${protocolSrc} --strip-components=1 \
      -C "$nm/@deepseek-ai/dsh-hook-protocol"

    # Kernel peers resolve from the composed tree; link instead of copying.
    for pkg in \
      "$nm/@deepseek-ai/dsh-hooks-claude-code" \
      "$nm/@deepseek-ai/dsh-hook-protocol"; do
      ln -s ${kernelNodeModules} "$pkg/node_modules"
    done

    cat > "$nm/dsh-orca-hooks/package.json" <<EOF
{
  "name": "dsh-orca-hooks",
  "version": "${version}",
  "private": true,
  "dependencies": {
    "@deepseek-ai/dsh-hooks-claude-code": "${version}",
    "@deepseek-ai/dsh-hook-protocol": "${version}"
  },
  "dsh": { "bundle": { "patch": "./cordis.patch.yml" } }
}
EOF

    # The bundle itself inserts nothing; Orca's home patch inserts the plugin.
    printf '[]\n' > "$nm/dsh-orca-hooks/cordis.patch.yml"

    # Key order must match the resolver's bundleMetadata JSON.stringify:
    # name, version, patch, packageRoot.
    cat > "$out/nix-support/dsh-bundles.json" <<EOF
{"schema":1,"bundles":[{"name":"dsh-orca-hooks","version":"${version}","patch":"./cordis.patch.yml","packageRoot":"$nm/dsh-orca-hooks"}]}
EOF

    runHook postInstall
  '';

  passthru = {
    dshBundle = true;
    dshBundleHelper = "buildDshBundle";
    runtimeDeps = [ ];
  };

  meta = {
    description = "Minimal dsh bundle supplying Orca's Claude Code hook bridge packages";
    platforms = lib.platforms.unix;
  };
}