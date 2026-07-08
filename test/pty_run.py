#!/usr/bin/env python3
"""Run init.sh under a pseudo-tty, feeding canned answers to its prompts.

The Upgrade/Cancel menu (and the working-memory-dir prompt) only fire when the
installer sees a real tty, so bats can't reach them through a closed stdin. This
allocates a pty, writes the canned keystrokes from $WMK_TTY_INPUT up front, and
relays the child's combined output. Kept as a file (not a bash heredoc) so the
quoting stays sane. Used only by run_installer_tty in helpers.bash.
"""
import os
import pty
import select
import signal
import sys
import time

kit = os.environ["WMK_KIT"]
feed = os.environ.get("WMK_TTY_INPUT", "").encode()
args = sys.argv[1:]

pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", os.path.join(kit, "init.sh"), *args])

if feed:
    os.write(fd, feed)

out = bytearray()
deadline = time.time() + 20
try:
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 5)
        if not r:
            break
        data = os.read(fd, 4096)
        if not data:
            break
        out += data
except OSError:
    # macOS raises EIO on the master once the slave closes; that's just EOF.
    pass

wpid, status = os.waitpid(pid, os.WNOHANG)
if wpid == 0:
    os.kill(pid, signal.SIGKILL)
    _, status = os.waitpid(pid, 0)

sys.stdout.buffer.write(out)
sys.stdout.buffer.flush()
sys.exit(os.waitstatus_to_exitcode(status))
