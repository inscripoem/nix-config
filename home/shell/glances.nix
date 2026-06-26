{ pkgs, ... }:

# Glances GPU monitoring on NixOS requires two NixOS-specific fixes on
# top of upstream's defaults.
#
# (1) Python binding injection.
# The stock glances derivation does not depend on nvidia-ml-py, so its
# GPU view shows "disabled". glances is a buildPythonApplication, so
# its wrapper's PYTHONPATH is computed at build time from the
# `dependencies` attribute. A plain `overrideAttrs` on
# `propagatedBuildInputs` does *not* reach wrapPythonProgramsHook and
# leaves `import pynvml` failing at runtime — use `overridePythonAttrs`
# with `dependencies` instead.
#
# (2) Runtime library discovery.
# Even after pynvml imports, glances loads NVML via
# `ctypes.CDLL("libnvidia-ml.so.1")` (see glances/plugins/gpu/cards/
# nvidia.py). On NixOS the NVIDIA user-space libs live under
# /run/opengl-driver/lib (GLVND path managed by hardware.graphics),
# which is NOT in the default ld.so search path for ordinary user
# programs since NixOS 20.03 — only nvidia-smi and friends are patched
# with the proper RUNPATH. Without LD_LIBRARY_PATH the CDLL call fails
# with "cannot open shared object file", glances silently disables the
# NVIDIA plugin, and `glances --stdout-json gpu` returns `{"gpu": []}`.
# See https://wiki.nixos.org/wiki/OpenGL for the canonical statement
# of this NixOS-wide issue.
#
# Fix: wrap the binary so /run/opengl-driver/lib is appended to
# LD_LIBRARY_PATH. We use `--suffix` (not `--prefix`) so any user-set
# value still wins, and we point at the directory unconditionally:
# on hosts without an NVIDIA card the directory is either empty or
# holds mesa libs, so the suffix is a harmless no-op. This keeps the
# module portable across briefcase (NVIDIA Pascal, see
# hardware/briefcase/gpu/nvidia-pascal.nix) and vm (vmware guest).
#
# AMD / Intel monitoring is intentionally not enabled: neither host
# has a card that would benefit from pyamdgpuinfo / intel_gpu_top.

let
  glancesWithNvml = pkgs.glances.overridePythonAttrs (old: {
    dependencies = (old.dependencies or [ ]) ++ [
      pkgs.python3Packages.nvidia-ml-py
    ];
  });

  glancesWrapped = pkgs.symlinkJoin {
    name = "glances-${glancesWithNvml.version}";
    paths = [ glancesWithNvml ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/glances \
        --suffix LD_LIBRARY_PATH : /run/opengl-driver/lib
    '';
    inherit (glancesWithNvml) meta;
  };
in
{
  home.packages = [ glancesWrapped ];
}
