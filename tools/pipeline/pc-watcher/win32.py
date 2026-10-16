"""Win32 helpers via ctypes: processes, a separate desktop for Studio, its windows, focus guard.

Background-only: Studio runs on its own Win32 desktop ("pcw-studio", CreateDesktopW +
CreateProcessW with lpDesktop), so it can never take the foreground on the user's desktop. Window
operations (find, resize) run on a DesktopWorker thread attached to that desktop. Nothing here
activates a window, changes the foreground or sends OS input. Frames come from StudioMCP
screen_capture (watcher.py), not from a window capture.

Imports fine on any OS; every function that needs user32/gdi32 calls _api() first,
which raises OSError off Windows. parse_tasklist_csv is pure (selftest.py).
"""

import csv
import ctypes
import io
import logging
import os
import queue
import subprocess
import threading
import time

STUDIO_IMAGE = "RobloxStudioBeta.exe"
NO_WINDOW = 0x08000000
DESKTOP_NAME = "pcw-studio"
GENERIC_ALL = 0x10000000

log = logging.getLogger("pcw.win32")

_API = None


def _api():
    global _API
    if _API is not None:
        return _API
    if os.name != "nt":
        raise OSError("Win32 API is only available on Windows")
    from ctypes import wintypes as wt

    user32 = ctypes.WinDLL("user32", use_last_error=True)
    gdi32 = ctypes.WinDLL("gdi32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

    WNDENUMPROC = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)

    class WINDOWPLACEMENT(ctypes.Structure):
        _fields_ = [("length", wt.UINT), ("flags", wt.UINT), ("showCmd", wt.UINT), ("ptMinPosition", wt.POINT),
                    ("ptMaxPosition", wt.POINT), ("rcNormalPosition", wt.RECT)]

    class STARTUPINFOW(ctypes.Structure):
        _fields_ = [
            ("cb", wt.DWORD), ("lpReserved", wt.LPWSTR), ("lpDesktop", wt.LPWSTR), ("lpTitle", wt.LPWSTR),
            ("dwX", wt.DWORD), ("dwY", wt.DWORD), ("dwXSize", wt.DWORD), ("dwYSize", wt.DWORD),
            ("dwXCountChars", wt.DWORD), ("dwYCountChars", wt.DWORD), ("dwFillAttribute", wt.DWORD),
            ("dwFlags", wt.DWORD), ("wShowWindow", wt.WORD), ("cbReserved2", wt.WORD),
            ("lpReserved2", ctypes.c_void_p), ("hStdInput", wt.HANDLE), ("hStdOutput", wt.HANDLE),
            ("hStdError", wt.HANDLE),
        ]

    class PROCESS_INFORMATION(ctypes.Structure):
        _fields_ = [("hProcess", wt.HANDLE), ("hThread", wt.HANDLE), ("dwProcessId", wt.DWORD),
                    ("dwThreadId", wt.DWORD)]

    sig = {
        (user32, "EnumDesktopWindows"): (wt.BOOL, [wt.HANDLE, WNDENUMPROC, wt.LPARAM]),
        (user32, "CreateDesktopW"): (wt.HANDLE, [wt.LPCWSTR, wt.LPCWSTR, ctypes.c_void_p, wt.DWORD, wt.DWORD, ctypes.c_void_p]),
        (user32, "OpenDesktopW"): (wt.HANDLE, [wt.LPCWSTR, wt.DWORD, wt.BOOL, wt.DWORD]),
        (user32, "CloseDesktop"): (wt.BOOL, [wt.HANDLE]),
        (user32, "SetThreadDesktop"): (wt.BOOL, [wt.HANDLE]),
        (kernel32, "CreateProcessW"): (wt.BOOL, [wt.LPCWSTR, wt.LPWSTR, ctypes.c_void_p, ctypes.c_void_p, wt.BOOL, wt.DWORD,
                                                  ctypes.c_void_p, wt.LPCWSTR, ctypes.POINTER(STARTUPINFOW),
                                                  ctypes.POINTER(PROCESS_INFORMATION)]),
        (user32, "GetWindowThreadProcessId"): (wt.DWORD, [wt.HWND, ctypes.POINTER(wt.DWORD)]),
        (user32, "IsWindowVisible"): (wt.BOOL, [wt.HWND]),
        (user32, "IsIconic"): (wt.BOOL, [wt.HWND]),
        (user32, "IsZoomed"): (wt.BOOL, [wt.HWND]),
        (user32, "GetWindowTextLengthW"): (ctypes.c_int, [wt.HWND]),
        (user32, "GetWindowTextW"): (ctypes.c_int, [wt.HWND, wt.LPWSTR, ctypes.c_int]),
        (user32, "GetWindowRect"): (wt.BOOL, [wt.HWND, ctypes.POINTER(wt.RECT)]),
        (user32, "GetClientRect"): (wt.BOOL, [wt.HWND, ctypes.POINTER(wt.RECT)]),
        (user32, "GetWindow"): (wt.HWND, [wt.HWND, wt.UINT]),
        (user32, "SetWindowPos"): (wt.BOOL, [wt.HWND, wt.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wt.UINT]),
        (user32, "GetWindowPlacement"): (wt.BOOL, [wt.HWND, ctypes.POINTER(WINDOWPLACEMENT)]),
        (user32, "GetSystemMetrics"): (ctypes.c_int, [ctypes.c_int]),
        (user32, "GetForegroundWindow"): (wt.HWND, []),
        (user32, "GetCursorPos"): (wt.BOOL, [ctypes.POINTER(wt.POINT)]),
        (user32, "PostMessageW"): (wt.BOOL, [wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM]),
        (kernel32, "OpenProcess"): (wt.HANDLE, [wt.DWORD, wt.BOOL, wt.DWORD]),
        (kernel32, "GetExitCodeProcess"): (wt.BOOL, [wt.HANDLE, ctypes.POINTER(wt.DWORD)]),
        (kernel32, "CloseHandle"): (wt.BOOL, [wt.HANDLE]),
    }
    for (dll, name), (res, args) in sig.items():
        fn = getattr(dll, name)
        fn.restype = res
        fn.argtypes = args

    class API:
        pass

    a = API()
    a.wt, a.user32, a.gdi32, a.kernel32 = wt, user32, gdi32, kernel32
    a.WNDENUMPROC = WNDENUMPROC
    a.WINDOWPLACEMENT = WINDOWPLACEMENT
    a.STARTUPINFOW, a.PROCESS_INFORMATION = STARTUPINFOW, PROCESS_INFORMATION
    _API = a
    return a


def set_dpi_aware():
    """Per-monitor DPI aware, so window sizes are physical pixels like Roblox's ViewportSize."""
    if os.name != "nt":
        return False
    try:
        return ctypes.windll.shcore.SetProcessDpiAwareness(2) == 0
    except Exception:
        try:
            return bool(ctypes.windll.user32.SetProcessDPIAware())
        except Exception:
            return False


# ---------------------------------------------------------------------------
# Processes
# ---------------------------------------------------------------------------

def parse_tasklist_csv(text):
    """`tasklist /FO CSV /NH` output -> [(image, pid)]."""
    out = []
    for row in csv.reader(io.StringIO(text)):
        if len(row) >= 2 and row[1].strip().isdigit():
            out.append((row[0], int(row[1])))
    return out


def descendants(table, roots):
    """table: [(pid, ppid, image)] -> roots plus every process whose parent chain reaches them."""
    out = set(int(r) for r in roots)
    grew = True
    while grew:
        grew = False
        for pid, ppid, _ in table:
            if ppid in out and pid not in out:
                out.add(pid)
                grew = True
    return out


def process_table():
    """[(pid, ppid, image)] via a Toolhelp32 snapshot."""
    a = _api()
    from ctypes import wintypes as wt

    class PROCESSENTRY32W(ctypes.Structure):
        _fields_ = [
            ("dwSize", wt.DWORD), ("cntUsage", wt.DWORD), ("th32ProcessID", wt.DWORD),
            ("th32DefaultHeapID", ctypes.c_void_p), ("th32ModuleID", wt.DWORD), ("cntThreads", wt.DWORD),
            ("th32ParentProcessID", wt.DWORD), ("pcPriClassBase", ctypes.c_long), ("dwFlags", wt.DWORD),
            ("szExeFile", ctypes.c_wchar * 260),
        ]

    k = a.kernel32
    k.CreateToolhelp32Snapshot.restype = wt.HANDLE
    k.CreateToolhelp32Snapshot.argtypes = [wt.DWORD, wt.DWORD]
    k.Process32FirstW.argtypes = [wt.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
    k.Process32NextW.argtypes = [wt.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
    snap = k.CreateToolhelp32Snapshot(0x2, 0)  # TH32CS_SNAPPROCESS
    if not snap or snap == ctypes.c_void_p(-1).value:
        return []
    out = []
    try:
        e = PROCESSENTRY32W()
        e.dwSize = ctypes.sizeof(PROCESSENTRY32W)
        ok = k.Process32FirstW(snap, ctypes.byref(e))
        while ok:
            out.append((e.th32ProcessID, e.th32ParentProcessID, e.szExeFile))
            ok = k.Process32NextW(snap, ctypes.byref(e))
    finally:
        k.CloseHandle(snap)
    return out


def list_pids(image=STUDIO_IMAGE):
    if os.name != "nt":
        return []
    try:
        return [pid for pid, _, img in process_table() if img.lower() == image.lower()]
    except Exception:
        pass
    r = subprocess.run(
        ["tasklist", "/FO", "CSV", "/NH", "/FI", "IMAGENAME eq %s" % image],
        capture_output=True, text=True, timeout=30, creationflags=NO_WINDOW,
    )
    return [pid for img, pid in parse_tasklist_csv(r.stdout) if img.lower() == image.lower()]


def pid_alive(pid):
    if os.name != "nt":
        return False
    a = _api()
    h = a.kernel32.OpenProcess(0x1000, False, int(pid))  # PROCESS_QUERY_LIMITED_INFORMATION
    if not h:
        return False
    try:
        code = a.wt.DWORD()
        return bool(a.kernel32.GetExitCodeProcess(h, ctypes.byref(code))) and code.value == 259  # STILL_ACTIVE
    finally:
        a.kernel32.CloseHandle(h)


def kill_pid(pid, tree=True):
    if os.name != "nt":
        return False
    args = ["taskkill", "/PID", str(int(pid)), "/F"] + (["/T"] if tree else [])
    r = subprocess.run(args, capture_output=True, text=True, timeout=30, creationflags=NO_WINDOW)
    return r.returncode == 0


# ---------------------------------------------------------------------------
# Windows
# ---------------------------------------------------------------------------

def _title(a, hwnd):
    n = a.user32.GetWindowTextLengthW(hwnd)
    buf = ctypes.create_unicode_buffer(n + 1)
    a.user32.GetWindowTextW(hwnd, buf, n + 1)
    return buf.value


def top_windows(pids=None, hdesk=None):
    """Top-level windows -> [{hwnd, pid, title, visible, iconic, owned, w, h, nw, nh}] (only `pids` if given).

    Every top-level window of the pid, whatever its visibility: Studio launched SW_SHOWMINNOACTIVE
    has an iconic main window whose GetWindowRect is a tiny caption at -32000, so nw/nh (the
    restored size, rcNormalPosition) is the size to judge it by. With `hdesk` the windows of that desktop
    are enumerated (EnumDesktopWindows); call it from a thread attached to the desktop (DesktopWorker).
    """
    a = _api()
    wanted = set(int(p) for p in pids) if pids is not None else None
    found = []

    def cb(hwnd, _):
        pid = a.wt.DWORD()
        a.user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if wanted is None or pid.value in wanted:
            r = a.wt.RECT()
            a.user32.GetWindowRect(hwnd, ctypes.byref(r))
            pl = _placement(a, hwnd)
            n = pl.rcNormalPosition if pl else r
            found.append({
                "hwnd": hwnd, "pid": pid.value, "title": _title(a, hwnd),
                "visible": bool(a.user32.IsWindowVisible(hwnd)), "iconic": bool(a.user32.IsIconic(hwnd)),
                "owned": bool(a.user32.GetWindow(hwnd, GW_OWNER)),
                "w": r.right - r.left, "h": r.bottom - r.top, "nw": n.right - n.left, "nh": n.bottom - n.top,
            })
        return True

    if hdesk is None:
        a.user32.EnumWindows(a.WNDENUMPROC(cb), 0)
    else:
        a.user32.EnumDesktopWindows(hdesk, a.WNDENUMPROC(cb), 0)
    return found


def pick_main_window(wins):
    """Pure: the Studio main window among top_windows() rows, or None.

    Unowned titled windows only, visible or not (an iconic one counts). Prefers 'Roblox Studio'
    titles, then a restored size over 300x200, then the largest restored size. Falls back to any
    unowned window of the pid (like .NET's Process.MainWindowHandle) when none has a title yet.
    """
    def area(w):
        return max(0, w.get("nw", w["w"])) * max(0, w.get("nh", w["h"]))

    def big(w):
        return w.get("nw", w["w"]) > 300 and w.get("nh", w["h"]) > 200

    unowned = [w for w in wins if not w.get("owned")]
    titled = [w for w in unowned if w["title"]]
    for pool in ([w for w in titled if "roblox studio" in w["title"].lower()], titled, unowned):
        if pool:
            return max(pool, key=lambda w: (big(w), w["visible"] or w.get("iconic", False), area(w)))
    return None


def studio_main_window(pids, hdesk=None):
    """Largest main window of `pids` (visible, hidden or minimized), or None."""
    return pick_main_window(top_windows(pids, hdesk))


def window_pid(hwnd):
    a = _api()
    pid = a.wt.DWORD()
    a.user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return pid.value


def title_has_place(title):
    """Studio titles a window with a loaded place as '<place> - Roblox Studio'; the start page is just 'Roblox Studio'."""
    t = (title or "").strip()
    low = t.lower()
    return "roblox studio" in low and low != "roblox studio" and " - " in t


def title_of(hwnd):
    return _title(_api(), hwnd)


def client_size(hwnd):
    a = _api()
    r = a.wt.RECT()
    a.user32.GetClientRect(hwnd, ctypes.byref(r))
    return r.right - r.left, r.bottom - r.top


def window_rect(hwnd):
    a = _api()
    r = a.wt.RECT()
    a.user32.GetWindowRect(hwnd, ctypes.byref(r))
    return r.left, r.top, r.right - r.left, r.bottom - r.top


SWP_NOZORDER, SWP_NOACTIVATE, SWP_NOOWNERZORDER = 0x0004, 0x0010, 0x0200
SWP_QUIET = SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER  # never activates, never reorders
STARTF_USESHOWWINDOW = 0x1
SW_SHOWNOACTIVATE = 4
GW_OWNER = 4


def create_desktop(name=DESKTOP_NAME):
    """CreateDesktopW(name, ..., GENERIC_ALL): Studio's own desktop (an existing one of that name is opened).
    Returns the handle; CloseDesktop it with close_desktop at the end of the run."""
    a = _api()
    h = a.user32.CreateDesktopW(name, None, None, 0, GENERIC_ALL, None)
    if not h:
        raise OSError("CreateDesktopW(%s) failed (%d)" % (name, ctypes.get_last_error()))
    return h


def close_desktop(hdesk):
    if not hdesk:
        return False
    return bool(_api().user32.CloseDesktop(hdesk))


class Launched:
    """A process started by launch_on_desktop (pid only; the handles are closed)."""

    def __init__(self, pid):
        self.pid = pid


def launch_on_desktop(args, cwd=None, desktop=DESKTOP_NAME):
    """CreateProcessW with STARTUPINFOW.lpDesktop = desktop: the process and its windows live on that
    desktop, so nothing it does can take focus on the user's desktop. Returns Launched(pid)."""
    a = _api()
    si = a.STARTUPINFOW()
    si.cb = ctypes.sizeof(a.STARTUPINFOW)
    si.lpDesktop = desktop
    si.dwFlags = STARTF_USESHOWWINDOW
    si.wShowWindow = SW_SHOWNOACTIVATE
    pi = a.PROCESS_INFORMATION()
    cmdline = ctypes.create_unicode_buffer(subprocess.list2cmdline([str(x) for x in args]))
    if not a.kernel32.CreateProcessW(None, cmdline, None, None, False, 0, None, cwd, ctypes.byref(si), ctypes.byref(pi)):
        raise OSError("CreateProcessW failed (%d)" % ctypes.get_last_error())
    a.kernel32.CloseHandle(pi.hThread)
    a.kernel32.CloseHandle(pi.hProcess)
    return Launched(pi.dwProcessId)


class DesktopWorker:
    """A dedicated thread attached to the Studio desktop (OpenDesktopW + SetThreadDesktop).

    SetThreadDesktop fails on a thread that owns windows or hooks, so this is a fresh
    threading.Thread that never creates any. Window calls on the desktop's windows (find,
    resize, size queries) are marshalled to it with call(fn, *args).
    """

    def __init__(self, name=DESKTOP_NAME):
        self.name = name
        self.hdesk = None
        self._q = queue.Queue()
        self._ready = threading.Event()
        self._err = None
        self._t = threading.Thread(target=self._run, name="pcw-desktop", daemon=True)
        self._t.start()
        self._ready.wait(15)
        if self._err:
            raise OSError(self._err)

    def _run(self):
        try:
            a = _api()
            self.hdesk = a.user32.OpenDesktopW(self.name, 0, False, GENERIC_ALL)
            if not self.hdesk:
                raise OSError("OpenDesktopW(%s) failed (%d)" % (self.name, ctypes.get_last_error()))
            if not a.user32.SetThreadDesktop(self.hdesk):
                raise OSError("SetThreadDesktop failed (%d)" % ctypes.get_last_error())
        except Exception as e:
            self._err = "desktop worker: %s" % (e,)
            return
        finally:
            self._ready.set()
        while True:
            job = self._q.get()
            if job is None:
                break
            fn, args, box, done = job
            try:
                box.append((True, fn(*args)))
            except Exception as e:
                box.append((False, e))
            done.set()
        _api().user32.CloseDesktop(self.hdesk)

    def call(self, fn, *args, timeout=60):
        """Runs fn(*args) on the desktop thread; returns its result or re-raises its exception."""
        box, done = [], threading.Event()
        self._q.put((fn, args, box, done))
        if not done.wait(timeout):
            raise TimeoutError("desktop worker call timed out: %s" % getattr(fn, "__name__", fn))
        ok, val = box[0]
        if not ok:
            raise val
        return val

    def main_window(self, pids):
        """Largest top-level window of `pids` on the desktop (EnumDesktopWindows), or None."""
        return self.call(studio_main_window, pids, self.hdesk)

    def close(self):
        if self._t.is_alive():
            self._q.put(None)
            self._t.join(5)


def _placement(a, hwnd):
    pl = a.WINDOWPLACEMENT()
    pl.length = ctypes.sizeof(a.WINDOWPLACEMENT)
    return pl if a.user32.GetWindowPlacement(hwnd, ctypes.byref(pl)) else None


def set_client_size(hwnd, cw, ch):
    """Resizes so the client area is cw x ch at 0,0 (SetWindowPos SWP_NOZORDER | SWP_NOACTIVATE |
    SWP_NOOWNERZORDER). Windows / Studio may clamp. Returns the client size reached. Run it on the
    DesktopWorker thread."""
    a = _api()
    _, _, ww, wh = window_rect(hwnd)
    cur_w, cur_h = client_size(hwnd)
    fw, fh = ww - cur_w, wh - cur_h  # frame + title bar
    a.user32.SetWindowPos(hwnd, None, 0, 0, int(cw + fw), int(ch + fh), SWP_QUIET)
    time.sleep(0.3)
    return client_size(hwnd)


def foreground_hwnd():
    return _api().user32.GetForegroundWindow()


def foreground_pid():
    """(hwnd, pid) of the foreground window; pid 0 when there is none."""
    h = foreground_hwnd()
    return h, (window_pid(h) if h else 0)


def focus_stolen(fg_pid, our_pids):
    """Pure: the foreground window belongs to a Studio process the watcher started."""
    return bool(fg_pid) and int(fg_pid) in set(int(p) for p in our_pids)


def cursor_pos():
    a = _api()
    pt = a.wt.POINT()
    a.user32.GetCursorPos(ctypes.byref(pt))
    return pt.x, pt.y


def post_close(hwnd):
    """WM_CLOSE by PostMessage: asks the window to close without activating it."""
    return bool(_api().user32.PostMessageW(hwnd, 0x0010, 0, 0))


def disable_power_throttling(pid):
    """Opt a process out of Windows background power throttling (EcoQoS / timer coalescing), which
    otherwise drops a background Studio to ~15 fps after a few minutes. SetProcessInformation(ProcessPowerThrottling): no window, focus or input involved."""
    try:
        import ctypes
        from ctypes import wintypes as wt

        class PPT(ctypes.Structure):
            _fields_ = [("Version", wt.ULONG), ("ControlMask", wt.ULONG), ("StateMask", wt.ULONG)]

        k = ctypes.windll.kernel32
        h = k.OpenProcess(0x0200, False, int(pid))  # PROCESS_SET_INFORMATION
        if not h:
            return False
        s = PPT(1, 0x1 | 0x4, 0)  # EXECUTION_SPEED | IGNORE_TIMER_RESOLUTION, state off
        ok = bool(k.SetProcessInformation(h, 4, ctypes.byref(s), ctypes.sizeof(s)))  # ProcessPowerThrottling
        k.CloseHandle(h)
        return ok
    except Exception:
        return False
