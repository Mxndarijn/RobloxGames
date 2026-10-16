"""Win32 helpers via ctypes: processes, Studio windows, off-screen sizing, PrintWindow capture.

Background-only: nothing here activates a window, changes the foreground or sends OS input.
Studio starts minimized-not-active, is moved left of all monitors with SetWindowPlacement
(SW_SHOWNOACTIVATE), resized with SetWindowPos(SWP_NOACTIVATE | ...), captured with
PrintWindow(PW_RENDERFULLCONTENT) and closed with a posted WM_CLOSE.

Imports fine on any OS; every function that needs user32/gdi32 calls _api() first,
which raises OSError off Windows. parse_tasklist_csv is pure (selftest.py).
"""

import csv
import ctypes
import io
import os
import subprocess
import time

import imaging

STUDIO_IMAGE = "RobloxStudioBeta.exe"
NO_WINDOW = 0x08000000

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

    sig = {
        (user32, "EnumWindows"): (wt.BOOL, [WNDENUMPROC, wt.LPARAM]),
        (user32, "GetWindowThreadProcessId"): (wt.DWORD, [wt.HWND, ctypes.POINTER(wt.DWORD)]),
        (user32, "IsWindowVisible"): (wt.BOOL, [wt.HWND]),
        (user32, "IsIconic"): (wt.BOOL, [wt.HWND]),
        (user32, "IsZoomed"): (wt.BOOL, [wt.HWND]),
        (user32, "GetWindowTextLengthW"): (ctypes.c_int, [wt.HWND]),
        (user32, "GetWindowTextW"): (ctypes.c_int, [wt.HWND, wt.LPWSTR, ctypes.c_int]),
        (user32, "GetWindowRect"): (wt.BOOL, [wt.HWND, ctypes.POINTER(wt.RECT)]),
        (user32, "GetClientRect"): (wt.BOOL, [wt.HWND, ctypes.POINTER(wt.RECT)]),
        (user32, "ClientToScreen"): (wt.BOOL, [wt.HWND, ctypes.POINTER(wt.POINT)]),
        (user32, "GetWindow"): (wt.HWND, [wt.HWND, wt.UINT]),
        (user32, "ShowWindow"): (wt.BOOL, [wt.HWND, ctypes.c_int]),
        (user32, "GetWindowLongPtrW"): (ctypes.c_ssize_t, [wt.HWND, ctypes.c_int]),
        (user32, "SetWindowLongPtrW"): (ctypes.c_ssize_t, [wt.HWND, ctypes.c_int, ctypes.c_ssize_t]),
        (user32, "SetWindowPos"): (wt.BOOL, [wt.HWND, wt.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wt.UINT]),
        (user32, "GetWindowPlacement"): (wt.BOOL, [wt.HWND, ctypes.POINTER(WINDOWPLACEMENT)]),
        (user32, "SetWindowPlacement"): (wt.BOOL, [wt.HWND, ctypes.POINTER(WINDOWPLACEMENT)]),
        (user32, "GetSystemMetrics"): (ctypes.c_int, [ctypes.c_int]),
        (user32, "GetForegroundWindow"): (wt.HWND, []),
        (user32, "GetCursorPos"): (wt.BOOL, [ctypes.POINTER(wt.POINT)]),
        (user32, "PostMessageW"): (wt.BOOL, [wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM]),
        (user32, "GetDC"): (wt.HDC, [wt.HWND]),
        (user32, "ReleaseDC"): (ctypes.c_int, [wt.HWND, wt.HDC]),
        (user32, "PrintWindow"): (wt.BOOL, [wt.HWND, wt.HDC, wt.UINT]),
        (gdi32, "CreateCompatibleDC"): (wt.HDC, [wt.HDC]),
        (gdi32, "DeleteDC"): (wt.BOOL, [wt.HDC]),
        (gdi32, "CreateDIBSection"): (wt.HBITMAP, [wt.HDC, ctypes.c_void_p, wt.UINT, ctypes.POINTER(ctypes.c_void_p), wt.HANDLE, wt.DWORD]),
        (gdi32, "SelectObject"): (wt.HGDIOBJ, [wt.HDC, wt.HGDIOBJ]),
        (gdi32, "DeleteObject"): (wt.BOOL, [wt.HGDIOBJ]),
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


def top_windows(pids=None):
    """Top-level windows -> [{hwnd, pid, title, visible, iconic, owned, w, h, nw, nh}] (only `pids` if given).

    Every top-level window of the pid, whatever its visibility: Studio launched SW_SHOWMINNOACTIVE
    has an iconic main window whose GetWindowRect is a tiny caption at -32000, so nw/nh (the
    restored size, rcNormalPosition) is the size to judge it by.
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

    a.user32.EnumWindows(a.WNDENUMPROC(cb), 0)
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


def studio_main_window(pids):
    """Main window of `pids` (visible, hidden or minimized), or None."""
    return pick_main_window(top_windows(pids))


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
SW_HIDE, SW_SHOWMINNOACTIVE, SW_SHOWNOACTIVATE = 0, 7, 4
GWL_EXSTYLE, WS_EX_TOOLWINDOW, WS_EX_APPWINDOW = -20, 0x80, 0x40000
SWP_NOSIZE, SWP_NOMOVE, SWP_FRAMECHANGED = 0x0001, 0x0002, 0x0020
STARTF_USESHOWWINDOW = 0x1
SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN = 76, 77
OFFSCREEN_MARGIN = 100
GW_OWNER = 4
PW_RENDERFULLCONTENT = 2


def launch_background(args, cwd=None):
    """Popen with STARTUPINFO SW_SHOWMINNOACTIVE: the first window opens minimized and not active."""
    si = subprocess.STARTUPINFO()
    si.dwFlags |= STARTF_USESHOWWINDOW
    si.wShowWindow = SW_SHOWMINNOACTIVE
    return subprocess.Popen(args, cwd=cwd, startupinfo=si)


def offscreen_x(virtual_left, window_w, margin=OFFSCREEN_MARGIN):
    """Pure: left edge that puts a window_w wide window `margin` px left of every monitor."""
    return int(virtual_left) - int(window_w) - int(margin)


def virtual_origin():
    a = _api()
    return a.user32.GetSystemMetrics(SM_XVIRTUALSCREEN), a.user32.GetSystemMetrics(SM_YVIRTUALSCREEN)


def _placement(a, hwnd):
    pl = a.WINDOWPLACEMENT()
    pl.length = ctypes.sizeof(a.WINDOWPLACEMENT)
    return pl if a.user32.GetWindowPlacement(hwnd, ctypes.byref(pl)) else None


def place_offscreen(hwnd, w=None, h=None):
    """Un-minimizes `hwnd` to a normal window left of all monitors, without activating it.

    SetWindowPlacement with showCmd SW_SHOWNOACTIVATE and rcNormalPosition off-screen (w x h, default:
    its current restored size). It never restores or maximizes through ShowWindow and never sets the
    foreground window.
    Returns the window rect (x, y, w, h).
    """
    a = _api()
    pl = _placement(a, hwnd)
    if pl is None:
        raise OSError("GetWindowPlacement failed (%d)" % ctypes.get_last_error())
    n = pl.rcNormalPosition
    w = int(w or (n.right - n.left))
    h = int(h or (n.bottom - n.top))
    vx, vy = virtual_origin()
    x = offscreen_x(vx, w)
    n.left, n.top, n.right, n.bottom = x, vy, x + w, vy + h
    pl.flags = 0
    pl.showCmd = SW_SHOWNOACTIVATE
    if not a.user32.SetWindowPlacement(hwnd, ctypes.byref(pl)):
        raise OSError("SetWindowPlacement failed (%d)" % ctypes.get_last_error())
    time.sleep(0.3)
    return window_rect(hwnd)


def hide_taskbar_button(hwnd):
    """Removes the window's taskbar button without activating it (the user may click it by accident and
    steal focus): WS_EX_TOOLWINDOW on, WS_EX_APPWINDOW off, then ShowWindow SW_HIDE + SW_SHOWNOACTIVATE
    (the taskbar re-reads the style on show; neither call activates) and SetWindowPos with
    SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER. The only ShowWindow
    use in the watcher. Returns True when the style was changed (False = already a tool window)."""
    a = _api()
    ex = a.user32.GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
    new = (ex | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW
    if new == ex:
        return False
    a.user32.SetWindowLongPtrW(hwnd, GWL_EXSTYLE, new)
    a.user32.ShowWindow(hwnd, SW_HIDE)
    a.user32.ShowWindow(hwnd, SW_SHOWNOACTIVATE)
    a.user32.SetWindowPos(hwnd, None, 0, 0, 0, 0, SWP_QUIET | SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED)
    time.sleep(0.3)
    return True


def is_offscreen(hwnd):
    """True when the window rect lies entirely left of the virtual screen."""
    x, _, w, _ = window_rect(hwnd)
    return x + w <= virtual_origin()[0]


def set_client_size(hwnd, cw, ch):
    """Resizes so the client area is cw x ch, kept off-screen (SetWindowPos SWP_NOACTIVATE |
    SWP_NOZORDER | SWP_NOOWNERZORDER). Windows / Studio may clamp. Returns the client size reached."""
    a = _api()
    if a.user32.IsIconic(hwnd) or a.user32.IsZoomed(hwnd):
        place_offscreen(hwnd)  # SetWindowPlacement SW_SHOWNOACTIVATE, not SW_RESTORE
    _, _, ww, wh = window_rect(hwnd)
    cur_w, cur_h = client_size(hwnd)
    fw, fh = ww - cur_w, wh - cur_h  # frame + title bar
    nw, nh = int(cw + fw), int(ch + fh)
    vx, vy = virtual_origin()
    a.user32.SetWindowPos(hwnd, None, offscreen_x(vx, nw), vy, nw, nh, SWP_QUIET)
    time.sleep(0.3)
    return client_size(hwnd)


def set_window_rect(hwnd, x, y, w, h):
    _api().user32.SetWindowPos(hwnd, None, int(x), int(y), int(w), int(h), SWP_QUIET)


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


# ---------------------------------------------------------------------------
# Capture
# ---------------------------------------------------------------------------

def _dib(a, hdc, w, h):
    class BITMAPINFOHEADER(ctypes.Structure):
        _fields_ = [
            ("biSize", ctypes.c_uint32), ("biWidth", ctypes.c_int32), ("biHeight", ctypes.c_int32),
            ("biPlanes", ctypes.c_uint16), ("biBitCount", ctypes.c_uint16), ("biCompression", ctypes.c_uint32),
            ("biSizeImage", ctypes.c_uint32), ("biXPelsPerMeter", ctypes.c_int32), ("biYPelsPerMeter", ctypes.c_int32),
            ("biClrUsed", ctypes.c_uint32), ("biClrImportant", ctypes.c_uint32),
        ]

    bmi = (ctypes.c_byte * (ctypes.sizeof(BITMAPINFOHEADER) + 16))()
    hdr = BITMAPINFOHEADER.from_buffer(bmi)
    hdr.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    hdr.biWidth, hdr.biHeight = w, -h  # negative: top-down rows
    hdr.biPlanes, hdr.biBitCount, hdr.biCompression = 1, 32, 0
    bits = ctypes.c_void_p()
    hbmp = a.gdi32.CreateDIBSection(hdc, ctypes.byref(bmi), 0, ctypes.byref(bits), None, 0)
    return hbmp, bits


def _grab(hwnd):
    """PrintWindow(PW_RENDERFULLCONTENT) of the whole window, cropped to the client area.

    Works off-screen and unfocused: the window renders itself into our DC; nothing is read from
    the screen.
    """
    a = _api()
    wx, wy, ww, wh = window_rect(hwnd)
    cw, ch = client_size(hwnd)
    if ww <= 0 or wh <= 0 or cw <= 0 or ch <= 0:
        return None
    pt = a.wt.POINT(0, 0)
    a.user32.ClientToScreen(hwnd, ctypes.byref(pt))
    ox, oy = pt.x - wx, pt.y - wy  # client origin inside the window rect
    src = a.user32.GetDC(hwnd)
    mem = a.gdi32.CreateCompatibleDC(src)
    hbmp, bits = _dib(a, src, ww, wh)
    old = a.gdi32.SelectObject(mem, hbmp)
    try:
        if not a.user32.PrintWindow(hwnd, mem, PW_RENDERFULLCONTENT):
            return None
        rgb = imaging.bgra_to_rgb(ww, wh, ctypes.string_at(bits, ww * wh * 4))
    finally:
        a.gdi32.SelectObject(mem, old)
        a.gdi32.DeleteObject(hbmp)
        a.gdi32.DeleteDC(mem)
        a.user32.ReleaseDC(hwnd, src)
    return imaging.crop_rgb(ww, wh, rgb, ox, oy, cw, ch)  # clamps to the window bitmap


def capture_client(hwnd):
    """Client-area pixels of `hwnd` via PrintWindow(PW_RENDERFULLCONTENT), the only capture method.

    Returns {"w","h","rgb","method","stats","blank","tried"}; rgb is None when it failed.
    """
    try:
        got = _grab(hwnd)
    except Exception as e:
        got, err = None, "printwindow: %r" % (e,)
    else:
        err = None if got else "printwindow: failed"
    if not got:
        return {"w": 0, "h": 0, "rgb": None, "method": None, "stats": None, "blank": True, "tried": [err]}
    w, h, rgb = got
    stats = imaging.frame_stats(w, h, rgb)
    return {"w": w, "h": h, "rgb": rgb, "method": "printwindow", "stats": stats, "blank": imaging.is_blank(stats),
            "tried": ["printwindow: var=%.0f distinct=%d" % (stats["variance"], stats["distinct"])]}


def disable_power_throttling(pid):
    """Opt a process out of Windows background power throttling (EcoQoS / timer coalescing), which
    otherwise drops a background, off-screen Studio to ~15 fps and blank PrintWindow frames after a
    few minutes. SetProcessInformation(ProcessPowerThrottling): no window, focus or input involved."""
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


def nudge_repaint(hwnd):
    """Forces a re-render of an off-screen window: grow the client by 1 px and back (no activation)."""
    cw, ch = client_size(hwnd)
    if cw and ch:
        set_client_size(hwnd, cw + 1, ch)
        set_client_size(hwnd, cw, ch)
