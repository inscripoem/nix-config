# ene-fanctl — userspace driver for the ENE 6K7750 motherboard ARGB
# controller (USB 0cf2:7750), found on the Maxsun MS-Terminator B760M D4.
#
# Upstream (teamlocabit/ene-6k7750-rgb) is a single Python script
# reverse-engineered from the vendor DLLs; it speaks raw USB vendor
# control transfers because the chip's hidraw interface is a decoy that
# STALLs every request. Only writes to LED RAM (0xE300+) and the effect
# commit strobes — it never touches the fan PWM registers that also
# live on this chip.
#
# Nix packaging has exactly one trap: pyusb's libusb1 backend locates
# the library through ctypes.util.find_library, which on NixOS returns
# nothing (no ldconfig cache, and the lib output only carries the
# versioned soname). Verified live 2026-10-26: NoBackendError even with
# LD_LIBRARY_PATH set, because find_library ignores it entirely on
# Linux. The bin wrapper patches find_library to the store path before
# exec'ing the upstream script.
{
  lib,
  fetchFromGitHub,
  libusb1,
  python3,
  runCommand,
}:
let
  version = "0-unstable-2026-10-01";
  src = fetchFromGitHub {
    owner = "teamlocabit";
    repo = "ene-6k7750-rgb";
    rev = "4a063ebd48458ac1aa20bee3496c0b6c3c70e9c8";
    hash = "sha256-lvDLf0iCJNVQ4MxTzPUAGWMB7Ll2pGEC+DwUWswOKX0=";
  };
  pyEnv = python3.withPackages (ps: [ ps.pyusb ]);
in
runCommand "ene-fanctl-${version}"
{
  meta = {
    description = "ARGB control for ENE 6K7750 motherboard controllers (Maxsun et al.)";
    mainProgram = "ene-fanctl";
    license = lib.licenses.mit;
  };
}
''
  mkdir -p $out/bin $out/share/ene-fanctl
  cp ${src}/ene_fanctl.py $out/share/ene-fanctl/

  cat > $out/bin/ene-fanctl <<EOF
#!${pyEnv}/bin/python3
import ctypes.util, runpy
_orig = ctypes.util.find_library
_LIBUSB = "${libusb1}/lib/libusb-1.0.so.0"
def _nix_find(name):
    if name in ("usb-1.0", "usb"):
        return _LIBUSB
    return _orig(name)
ctypes.util.find_library = _nix_find
runpy.run_path("$out/share/ene-fanctl/ene_fanctl.py", run_name="__main__")
EOF
  chmod +x $out/bin/ene-fanctl
''
