#!/usr/bin/env python3
"""Compatibility smoke test for a built dsh TUI preset.

Runs the preset in a throwaway DSH_HOME under a PTY, copies only the user's
settings.yaml (never credentials), types one short prompt, and fails when
the TUI reports an engine-version validation warning or the known
undefined-property turn crash. Model/auth errors are environmental, not
compatibility failures, and do not fail the check.

Exit: 0 pass, 1 fail/inconclusive, 2 bad usage or missing preset.
"""

import fcntl
import os
import pty
import re
import select
import shutil
import signal
import struct
import sys
import tempfile
import termios
import time
from pathlib import Path

FAIL_PATTERNS = ("is newer than the", "Cannot read properties")
PASS_PATTERNS = ("dsh-TUI", "Say something", "Waiting on the muse")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check-dsh-tui.py <preset-store-path>", file=sys.stderr)
        return 2
    preset = sys.argv[1]
    binary = os.path.join(preset, "bin", "dsh")
    if not os.access(binary, os.X_OK):
        print(f"check-dsh-tui: no executable at {binary}", file=sys.stderr)
        return 2

    home = tempfile.mkdtemp(prefix="dsh-tui-smoke.")
    os.chmod(home, 0o700)
    settings = Path.home() / ".dsh" / "settings.yaml"
    if settings.is_file():
        try:
            target = Path(home) / "settings.yaml"
            shutil.copy2(settings, target)
            os.chmod(target, 0o600)
        except OSError:
            pass

    pid, fd = pty.fork()
    if pid == 0:  # child
        os.environ["DSH_HOME"] = home
        os.environ.setdefault("TERM", "xterm-256color")
        try:
            os.execv(binary, [binary, "nix-tui"])
        except OSError:
            os._exit(127)

    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        buf = b""
        start = time.time()
        sent_text = False
        sent_enter = False
        while time.time() - start < 28:
            ready, _, _ = select.select([fd], [], [], 0.5)
            if ready:
                try:
                    chunk = os.read(fd, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                buf += chunk
            if not sent_text and time.time() - start > 8:
                os.write(fd, b"hi")
                sent_text = True
            if sent_text and not sent_enter and time.time() - start > 8.5:
                os.write(fd, b"\r")
                sent_enter = True
    finally:
        try:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        except OSError:
            pass
        os.close(fd)
        shutil.rmtree(home, ignore_errors=True)

    text = buf.decode("utf-8", "replace")
    clean = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)
    clean = re.sub(r"\x1b\][^\x07]*\x07", "", clean)

    hits = [line.strip() for line in clean.splitlines() if any(p in line for p in FAIL_PATTERNS)]
    if hits:
        print("check-dsh-tui: FAIL", file=sys.stderr)
        for line in hits[:4]:
            print(line, file=sys.stderr)
        return 1

    if not any(p in clean for p in PASS_PATTERNS):
        print("check-dsh-tui: INCONCLUSIVE — no TUI prompt appeared", file=sys.stderr)
        for line in clean.splitlines()[-5:]:
            print(line, file=sys.stderr)
        return 1

    print("check-dsh-tui: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())