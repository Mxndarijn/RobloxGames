"""Win32 helpers via ctypes: processes, Studio windows, resizing, client-area capture.

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
        (user32, "SetWindowPos"): (wt.BOOL, [wt.HWND, wt.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wt.UINT]),
        (user32, "ShowWindow"): (wt.BOOL, [wt.HWND, ctypes.c_int]),
        (user32, "SetForegroundWindow"): (wt.BOOL, [wt.HWND]),
        (user32, "GetForegroundWindow"): (wt.HWND, []),
        (user32, "BringWindowToTop"): (wt.BOOL, [wt.HWND]),
        (user32, "keybd_event"): (None, [wt.BYTE, wt.BYTE, wt.DWORD, ctypes.c_void_p]),
        (user32, "PostMessageW"): (wt.BOOL, [wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM]),
        (user32, "GetDC"): (wt.HDC, [wt.HWND]),
        (user32, "ReleaseDC"): (ctypes.c_int, [wt.HWND, wt.HDC]),
        (user32, "PrintWindow"): (wt.BOOL, [wt.HWND, wt.HDC, wt.UINT]),
        (gdi32, "CreateCompatibleDC"): (wt.HDC, [wt.HDC]),
        (gdi32, "DeleteDC"): (wt.BOOL, [wt.HDC]),
        (gdi32, "CreateDIBSection"): (wt.HBITMAP, [wt.HDC, ctypes.c_void_p, wt.UINT, ctypes.POINTER(ctypes.c_void_p), wt.HANDLE, wt.DWORD]),
        (gdi32, "SelectObject"): (wt.HGDIOBJ, [wt.HDC, wt.HGDIOBJ]),
        (gdi32, "DeleteObject"): (wt.BOOL, [wt.HGDIOBJ]),
        (gdi32, "BitBlt"): (wt.BOOL, [wt.HDC, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wt.HDC, ctypes.c_int, ctypes.c_int, wt.DWORD]),
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
    """Top-level windows -> [{hwnd, pid, title, visible, w, h}] (only `pids` if given)."""
    a = _api()
    wanted = set(int(p) for p in pids) if pids is not None else None
    found = []

    def cb(hwnd, _):
        pid = a.wt.DWORD()
        a.user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if wanted is None or pid.value in wanted:
            r = a.wt.RECT()
            a.user32.GetWindowRect(hwnd, ctypes.byref(r))
            found.append({
                "hwnd": hwnd, "pid": pid.value, "title": _title(a, hwnd),
                "visible": bool(a.user32.IsWindowVisible(hwnd)),
                "w": r.right - r.left, "h": r.bottom - r.top,
            })
        return True

    a.user32.EnumWindows(a.WNDENUMPROC(cb), 0)
    return found


def studio_main_window(pids):
    """Largest visible titled window of `pids` that looks like the Studio main window, or None."""
    wins = [w for w in top_windows(pids) if w["visible"] and w["title"] and w["w"] > 300 and w["h"] > 200]
    studio = [w for w in wins if "roblox studio" in w["title"].lower()] or wins
    return max(studio, key=lambda w: w["w"] * w["h"]) if studio else None


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


def is_maximized(hwnd):
    return bool(_api().user32.IsZoomed(hwnd))


SWP_NOZORDER, SWP_NOACTIVATE, SWP_NOMOVE = 0x0004, 0x0010, 0x0002


def restore(hwnd):
    _api().user32.ShowWindow(hwnd, 9)  # SW_RESTORE


def maximize(hwnd):
    _api().user32.ShowWindow(hwnd, 3)  # SW_MAXIMIZE


def set_client_size(hwnd, cw, ch, x=None, y=None):
    """Resizes so the client area is cw x ch (Windows / Studio may clamp). Returns the client size reached."""
    a = _api()
    if a.user32.IsZoomed(hwnd) or a.user32.IsIconic(hwnd):
        restore(hwnd)
        time.sleep(0.4)
    left, top, ww, wh = window_rect(hwnd)
    cur_w, cur_h = client_size(hwnd)
    fw, fh = ww - cur_w, wh - cur_h  # frame + title bar
    flags = SWP_NOZORDER | SWP_NOACTIVATE
    if x is None:
        x, y = left, top
    a.user32.SetWindowPos(hwnd, None, int(x), int(y), int(cw + fw), int(ch + fh), flags)
    time.sleep(0.3)
    return client_size(hwnd)


def set_window_rect(hwnd, x, y, w, h):
    _api().user32.SetWindowPos(hwnd, None, int(x), int(y), int(w), int(h), SWP_NOZORDER | SWP_NOACTIVATE)


def bring_to_front(hwnd):
    """Best effort foreground (Windows refuses SetForegroundWindow from background apps; an Alt tap unlocks it)."""
    a = _api()
    if a.user32.IsIconic(hwnd):
        restore(hwnd)
    a.user32.keybd_event(0x12, 0, 0, None)  # Alt down
    a.user32.keybd_event(0x12, 0, 2, None)  # Alt up
    a.user32.BringWindowToTop(hwnd)
    a.user32.SetForegroundWindow(hwnd)
    time.sleep(0.3)
    return a.user32.GetForegroundWindow() == hwnd


def foreground_hwnd():
    return _api().user32.GetForegroundWindow()


def post_close(hwnd):
    return bool(_api().user32.PostMessageW(hwnd, 0x0010, 0, 0))  # WM_CLOSE


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


def _grab(hwnd, method):
    a = _api()
    w, h = client_size(hwnd)
    if w <= 0 or h <= 0:
        return None
    src_hwnd = None if method == "screen" else hwnd
    src = a.user32.GetDC(src_hwnd)
    mem = a.gdi32.CreateCompatibleDC(src)
    hbmp, bits = _dib(a, src, w, h)
    old = a.gdi32.SelectObject(mem, hbmp)
    try:
        if method == "printwindow":
            ok = a.user32.PrintWindow(hwnd, mem, 3)  # PW_CLIENTONLY | PW_RENDERFULLCONTENT
        elif method == "bitblt":
            ok = a.gdi32.BitBlt(mem, 0, 0, w, h, src, 0, 0, 0x00CC0020 | 0x40000000)  # SRCCOPY | CAPTUREBLT
        else:
            pt = a.wt.POINT(0, 0)
            a.user32.ClientToScreen(hwnd, ctypes.byref(pt))
            ok = a.gdi32.BitBlt(mem, 0, 0, w, h, src, pt.x, pt.y, 0x00CC0020 | 0x40000000)
        if not ok:
            return None
        raw = ctypes.string_at(bits, w * h * 4)
        return w, h, imaging.bgra_to_rgb(w, h, raw)
    finally:
        a.gdi32.SelectObject(mem, old)
        a.gdi32.DeleteObject(hbmp)
        a.gdi32.DeleteDC(mem)
        a.user32.ReleaseDC(src_hwnd, src)


def capture_client(hwnd, methods=("printwindow", "bitblt", "screen")):
    """Client-area pixels of `hwnd`: first method whose frame is not blank.

    Returns {"w","h","rgb","method","stats","blank","tried"}; rgb is None when every method failed.
    "screen" copies the desktop at the window's position, so it is only valid while the window is on top.
    """
    tried, last = [], None
    for m in methods:
        try:
            got = _grab(hwnd, m)
        except Exception as e:
            tried.append("%s: %r" % (m, e))
            continue
        if not got:
            tried.append("%s: failed" % m)
            continue
        w, h, rgb = got
        stats = imaging.frame_stats(w, h, rgb)
        blank = imaging.is_blank(stats)
        tried.append("%s: var=%.0f distinct=%d" % (m, stats["variance"], stats["distinct"]))
        last = {"w": w, "h": h, "rgb": rgb, "method": m, "stats": stats, "blank": blank}
        if not blank:
            break
    out = last or {"w": 0, "h": 0, "rgb": None, "method": None, "stats": None, "blank": True}
    out["tried"] = tried
    return out
