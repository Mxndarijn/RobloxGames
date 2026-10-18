"""Open Roblox Studio on a hidden Win32 desktop so it never takes focus on Merijn's screen.

    python studio_hidden.py open <place.rbxl>   # prints the pid; MCP sees Studio after ~10 s
    python studio_hidden.py close               # kills the Studio trees this script started (no save dialog)

Same mechanism as the watcher (see README "Runs in the background"), on its own desktop name so it does not
collide with a watcher run. Pids are kept in %LOCALAPPDATA%\\pcw-studio-hidden.pids.
"""
import os
import subprocess
import sys

import mcp_client
import win32

DESKTOP = "claude-studio"
PIDS = os.path.join(os.environ.get("LOCALAPPDATA", "."), "pcw-studio-hidden.pids")


def open_place(place):
    studio_dir = mcp_client.find_studio_dir()
    if not studio_dir:
        sys.exit("Roblox Studio not found under %LOCALAPPDATA%\\Roblox\\Versions")
    win32.create_desktop(DESKTOP)  # the desktop lives on while Studio is attached to it
    exe = os.path.join(studio_dir, "RobloxStudioBeta.exe")
    proc = win32.launch_on_desktop([exe, os.path.abspath(place)], cwd=studio_dir, desktop=DESKTOP)
    with open(PIDS, "a") as f:
        f.write("%d\n" % proc.pid)
    print(proc.pid)


def close_all():
    if not os.path.isfile(PIDS):
        return
    with open(PIDS) as f:
        pids = [line.strip() for line in f if line.strip()]
    for pid in pids:
        # TerminateProcess on the tree: no WM_CLOSE, so no "Save changes?" dialog and no activation.
        subprocess.run(["taskkill", "/T", "/F", "/PID", pid], capture_output=True, creationflags=win32.NO_WINDOW)
    os.remove(PIDS)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "open":
        open_place(sys.argv[2])
    elif len(sys.argv) == 2 and sys.argv[1] == "close":
        close_all()
    else:
        sys.exit(__doc__)
