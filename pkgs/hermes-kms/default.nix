# hermes-kms — out-of-tree DRM/KMS virtual-display kernel module for Hermes
# (MrOz59/Hermes-KMS). Loaded at boot with the connector disconnected
# (`initial_enabled=0`, set via boot.extraModprobeConfig in the hermes
# capability); Hermes connects the virtual output only while a streaming
# session owns it, and compositors adopt it as a normal hotplug.
#
# Derivation shape borrowed from sachk/hermes-nix (the only existing Nix
# packaging, pinned to an old fork) with the source moved upstream and the
# update mechanism brought in-repo. `kernelModuleMakeFlags` does not exist
# in this nixpkgs pin, so the standard kernel.makeFlags carry the
# cross/compiler flags.
#
# Update mechanism: `scripts/update-versions.sh --only=hermes-kms` bumps
# `version` and refreshes the source hash (no submodules, so a plain
# tarball prefetch suffices). Pairing rule: verify against the running
# Hermes with `GET /api/hestia/v1/diagnostics` after every bump — upstream
# does not publish an explicit driver-per-Hermes table past 0.6.0→v0.4.0,
# and the readiness report is the arbiter.
{
  lib,
  stdenv,
  fetchFromGitHub,
  kernel,
  # Kernel-modules scoped flags from the same linuxPackages set as `kernel`
  # (KBUILD_OUTPUT, toolchain paths, DEPMOD=true). Not a top-level pkgs
  # attribute — the caller passes it alongside the kernel.
  kernelModuleMakeFlags,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "hermes-kms";
  version = "0.4.1";

  src = fetchFromGitHub {
    owner = "MrOz59";
    repo = "Hermes-KMS";
    tag = "v${finalAttrs.version}";
    hash = "sha256-hx7Ic/ErPeveuStjIGQB5nNKSpdcKJ5fFodZzEipvic=";
  };

  __structuredAttrs = true;
  strictDeps = true;

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = kernelModuleMakeFlags ++ [
    "KERNELRELEASE=${kernel.modDirVersion}"
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "INSTALL_MOD_PATH=${placeholder "out"}"
    "INSTALL_MOD_DIR=extra"
  ];

  buildFlags = [ "modules" ];

  # The upstream Makefile has no install target; add a modules_install
  # passthrough with the same $(PWD) handling as its modules target.
  # Installing must go through kbuild's modules_install — not a raw .ko
  # copy: NixOS' kernelModuleMakeFlags hook cmd_sign into kmodigest, which
  # signs the module and writes hermes_kms.ko.cer, the per-module
  # certificate the kernel modules aggregator collects. A plain install
  # of the unsigned .ko breaks that aggregate with "cat:
  # extra/hermes_kms.ko.cer: No such file or directory" (same mechanism
  # as nixpkgs' broadcom-sta).
  postPatch = ''
    printf '\nmodules_install:\n\t$(MAKE) -C $(KDIR) M=$(PWD)/kernel/hermes-kms $(LLVM_FLAG) modules_install\n' >> Makefile
  '';

  # Kernel modules trip over userspace hardening flags; the community
  # packaging disables the same three.
  hardeningDisable = [
    "format"
    "fortify"
    "pic"
  ];

  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall

    make modules_install "''${makeFlags[@]}"

    # udev rules for the render nodes, with the upstream FHS helper path
    # rewritten to this output — NixOS' udev-rules builder rejects dangling
    # absolute paths (same failure class as the session-broker rule in the
    # hermes package). The session-seats and dev-ignore-seat rules are not
    # shipped: private-seat brokers are out of scope (wlroots-family
    # compositors cannot use them) and the other one is for modetest
    # development only.
    install -Dm0644 udev/72-hermes-kms-render-access.rules \
      "$out/lib/udev/rules.d/72-hermes-kms-render-access.rules"
    install -Dm0644 udev/92-hermes-kms-access.rules \
      "$out/lib/udev/rules.d/92-hermes-kms-access.rules"
    install -Dm0644 udev/95-hermes-kms-host-access.rules \
      "$out/lib/udev/rules.d/95-hermes-kms-host-access.rules"
    install -Dm0755 scripts/hermes-kms-render-acl \
      "$out/lib/hermes-kms/hermes-kms-render-acl"
    substituteInPlace "$out/lib/udev/rules.d/72-hermes-kms-render-access.rules" \
      --replace-fail '/usr/lib/hermes-kms/hermes-kms-render-acl' "$out/lib/hermes-kms/hermes-kms-render-acl"
    substituteInPlace "$out/lib/udev/rules.d/95-hermes-kms-host-access.rules" \
      --replace-fail '/usr/lib/hermes-kms/hermes-kms-render-acl' "$out/lib/hermes-kms/hermes-kms-render-acl"

    runHook postInstall
  '';

  passthru = {
    inherit kernel;
  };

  meta = {
    description = "Out-of-tree DRM/KMS virtual-display kernel module for Hermes";
    homepage = "https://github.com/MrOz59/Hermes-KMS";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
})
