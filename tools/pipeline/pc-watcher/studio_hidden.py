"""Open Roblox Studio on a hidden Win32 desktop so it never takes focus on Merijn's screen.

    python studio_hidden.py open <place.rbxl> [--timeout S] [--no-wait]
        Starts Studio, waits until its window shows the place (default up to 180 s), then prints the pid
        as the last stdout line. Keep that pid: it is how you close your own Studio again.
    python studio_hidden.py close <pid> [<pid> ...]
        Kills those Studio trees (no save dialog). Only pids this script started are touched.
    python studio_hidden.py close
        Kills only the Studios that were opened from this checkout (git worktree root of the cwd).
    python studio_hidden.py list
        Shows every Studio this script started that is still running: pid, owner checkout, place.

Several bots share this PC, so `close` never kills a Studio someone else opened, and never one Merijn
opened (pids not in the file are refused). Same mechanism as the watcher (see README "Runs in the
background"), on its own desktop name so it does not collide with a watcher run. Started Studios are
kept in %LOCALAPPDATA%\\pcw-studio-hidden.pids, one "pid<TAB>owner<TAB>place" line each.
"""
import os
import subprocess
import sys
import time

import mcp_client
import win32

DESKTOP = "claude-studio"
PIDS = os.path.join(os.environ.get("LOCALAPPDATA", "."), "pcw-studio-hidden.pids")
LOCK = PIDS + ".lock"


def owner():
    """The checkout this caller runs in: each bot has its own worktree, so this tells bots apart."""
    try:
        r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                           timeout=10, creationflags=win32.NO_WINDOW)
        if r.returncode == 0 and r.stdout.strip():
            return os.path.normcase(os.path.abspath(r.stdout.strip()))
    except (OSError, subprocess.SubprocessError):
        pass
    return os.path.normcase(os.path.abspath(os.getcwd()))


class Locked:
    """Exclusive lock on the pid file across processes (O_EXCL lock file; a stale one is broken after 30 s)."""

    def __enter__(self):
        deadline = time.time() + 30
        while True:
            try:
                os.close(os.open(LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
                return self
            except FileExistsError:
                try:
                    if time.time() - os.path.getmtime(LOCK) > 30:
                        os.remove(LOCK)
                        continue
                except OSError:
                    pass
                if time.time() > deadline:
                    sys.exit("pid file is locked: %s" % LOCK)
                time.sleep(0.1)

    def __exit__(self, *exc):
        try:
            os.remove(LOCK)
        except OSError:
            pass


def read_entries():
    """[{pid, owner, place}]; a bare "pid" line from the old format has no owner."""
    if not os.path.isfile(PIDS):
        return []
    out = []
    with open(PIDS, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if parts[0].strip().isdigit():
                out.append({"pid": int(parts[0]), "owner": parts[1] if len(parts) > 1 else "",
                            "place": parts[2] if len(parts) > 2 else ""})
    return out


def write_entries(entries):
    if not entries:
        if os.path.isfile(PIDS):
            os.remove(PIDS)
        return
    tmp = PIDS + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        for e in entries:
            f.write("%d\t%s\t%s\n" % (e["pid"], e["owner"], e["place"]))
    os.replace(tmp, PIDS)


def studio_alive(pid, table):
    """True while `pid` is a running Studio (a reused pid of another program does not count)."""
    return any(p == pid and img.lower() == win32.STUDIO_IMAGE.lower() for p, _, img in table)


def wait_loaded(pid, timeout):
    """Waits until a window of the Studio tree is titled '<place> - Roblox Studio'. Returns the title or None."""
    worker = win32.DesktopWorker(DESKTOP)
    try:
        deadline = time.time() + timeout
        while time.time() < deadline:
            table = win32.process_table()
            if not studio_alive(pid, table):
                sys.exit("Studio pid %d exited while loading" % pid)
            pids = win32.descendants(table, [pid])
            for w in worker.call(win32.top_windows, pids, worker.hdesk):
                if win32.title_has_place(w["title"]):
                    return w["title"]
            time.sleep(1)
        return None
    finally:
        worker.close()


def open_place(place, wait=True, timeout=180):
    studio_dir = mcp_client.find_studio_dir()
    if not studio_dir:
        sys.exit("Roblox Studio not found under %LOCALAPPDATA%\\Roblox\\Versions")
    place = os.path.abspath(place)
    if not os.path.isfile(place):
        sys.exit("place not found: %s" % place)
    hdesk = win32.create_desktop(DESKTOP)  # the desktop lives on while Studio is attached to it
    exe = os.path.join(studio_dir, "RobloxStudioBeta.exe")
    proc = win32.launch_on_desktop([exe, place], cwd=studio_dir, desktop=DESKTOP)
    with Locked():
        entries = read_entries()
        entries.append({"pid": proc.pid, "owner": owner(), "place": os.path.basename(place)})
        write_entries(entries)
    if wait:
        print("waiting for Studio pid %d to load %s ..." % (proc.pid, os.path.basename(place)), file=sys.stderr)
        t0 = time.time()
        title = wait_loaded(proc.pid, timeout)
        if title:
            # The window title appears a moment before the MCP plugin answers; a short margin avoids a first miss.
            time.sleep(5)
            print("loaded in %.0f s: %s" % (time.time() - t0, title), file=sys.stderr)
        else:
            print("Studio did not show the place within %d s; it is still running (close %d)" % (timeout, proc.pid),
                  file=sys.stderr)
    win32.close_desktop(hdesk)
    print(proc.pid)


def kill(pid):
    # TerminateProcess on the tree: no WM_CLOSE, so no "Save changes?" dialog and no activation.
    subprocess.run(["taskkill", "/T", "/F", "/PID", str(pid)], capture_output=True, creationflags=win32.NO_WINDOW)


def close(pids=None):
    """Kills `pids` (must be ours), or with none every Studio opened from this checkout. Prunes dead lines."""
    me = owner()
    with Locked():
        entries = read_entries()
        table = win32.process_table()
        known = {e["pid"] for e in entries}
        if pids:
            unknown = [p for p in pids if p not in known]
            if unknown:
                print("refused (not started by studio_hidden.py): %s" % unknown, file=sys.stderr)
            targets = [p for p in pids if p in known]
        else:
            targets = [e["pid"] for e in entries if e["owner"] == me]
        for pid in targets:
            if studio_alive(pid, table):
                kill(pid)
                print("closed %d" % pid)
            else:
                print("%d was already gone" % pid)
        keep = [e for e in entries if e["pid"] not in targets and studio_alive(e["pid"], table)]
        write_entries(keep)
        others = [e["pid"] for e in keep]
        if others:
            print("left running (other callers): %s" % others, file=sys.stderr)


def list_open():
    table = win32.process_table()
    for e in read_entries():
        if studio_alive(e["pid"], table):
            print("%d\t%s\t%s" % (e["pid"], e["owner"] or "?", e["place"]))


def main(argv):
    if len(argv) >= 2 and argv[0] == "open":
        args = argv[1:]
        wait = "--no-wait" not in args
        args = [a for a in args if a != "--no-wait"]
        timeout = 180
        if "--timeout" in args:
            i = args.index("--timeout")
            timeout = int(args[i + 1])
            del args[i:i + 2]
        if len(args) != 1:
            sys.exit(__doc__)
        open_place(args[0], wait, timeout)
    elif argv and argv[0] == "close" and all(a.isdigit() for a in argv[1:]):
        close([int(a) for a in argv[1:]])
    elif argv == ["list"]:
        list_open()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
