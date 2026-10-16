"""StudioMCP stdio JSON-RPC client (adapted from pc-watcher-ref/mcpcall.py) and result helpers.

The parsing / action-building helpers are pure so selftest.py can cover them.
"""

import base64
import glob
import json
import logging
import os
import queue
import re
import subprocess
import threading
import time
import uuid

PROTO = "2026-07-28"
log = logging.getLogger("pcw.mcp")

MARK_RE = r"@@PCW:%s@@(.*?)@@END@@"


# ---------------------------------------------------------------------------
# Locating Studio
# ---------------------------------------------------------------------------

def find_studio_dir(local_appdata=None):
    """Newest %LOCALAPPDATA%\\Roblox\\Versions\\<ver> that has both RobloxStudioBeta.exe and StudioMCP.exe.

    Falls back to a dir with just RobloxStudioBeta.exe (then MCP is unavailable). Returns None if none.
    """
    root = os.path.join(local_appdata or os.environ.get("LOCALAPPDATA", ""), "Roblox", "Versions")
    best, best_partial = None, None
    for d in glob.glob(os.path.join(root, "*")):
        studio = os.path.join(d, "RobloxStudioBeta.exe")
        if not os.path.isfile(studio):
            continue
        mtime = os.path.getmtime(studio)
        if os.path.isfile(os.path.join(d, "StudioMCP.exe")):
            if best is None or mtime > best[0]:
                best = (mtime, d)
        elif best_partial is None or mtime > best_partial[0]:
            best_partial = (mtime, d)
    pick = best or best_partial
    return pick[1] if pick else None


# ---------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------

class ToolResult:
    def __init__(self, tool, raw=None, error=None):
        self.tool = tool
        self.raw = raw or {}
        self.error = error  # driver / JSON-RPC error string
        self.texts, self.images = [], []
        for blk in self.raw.get("content", []) or []:
            if blk.get("type") == "text":
                self.texts.append(blk.get("text", ""))
            elif blk.get("type") == "image" and blk.get("data"):
                self.images.append((blk.get("mimeType", "image/png"), blk["data"]))
        self.structured = self.raw.get("structuredContent")
        self.is_error = bool(error) or bool(self.raw.get("isError"))

    @property
    def text(self):
        return "\n".join(self.texts)

    @property
    def ok(self):
        return not self.is_error

    def image_bytes(self):
        """First image block as (mime, bytes) or None."""
        if not self.images:
            return None
        mime, data = self.images[0]
        return mime, base64.b64decode(data)

    def brief(self, n=300):
        if self.error:
            return "ERROR " + str(self.error)[:n]
        return ("isError " if self.is_error else "") + self.text[:n].replace("\n", " | ")


def extract_marked(text, nonce):
    """Finds the @@PCW:<nonce>@@{json}@@END@@ payload in tool text (raw or JSON-string-escaped)."""
    if not text:
        return None
    for m in re.finditer(MARK_RE % re.escape(nonce), text, re.S):
        chunk = m.group(1)
        for candidate in (chunk, None):
            try:
                if candidate is None:
                    candidate = json.loads('"' + chunk + '"')  # text was a JSON-quoted string
                return json.loads(candidate)
            except Exception:
                continue
    return None


def wrap_luau(body, nonce):
    """Wraps a Luau function body (which returns a table) so the result comes back as marked JSON."""
    return (
        "local __HS = game:GetService(\"HttpService\")\n"
        "local __ok, __res = pcall(function()\n"
        + body
        + "\nend)\n"
        "local __enc_ok, __out = pcall(function()\n"
        "\treturn __HS:JSONEncode(if __ok then { ok = true, data = __res } else { ok = false, error = tostring(__res) })\n"
        "end)\n"
        "if not __enc_ok then __out = __HS:JSONEncode({ ok = false, error = \"encode: \" .. tostring(__out) }) end\n"
        "local __msg = \"@@PCW:" + nonce + "@@\" .. __out .. \"@@END@@\"\n"
        "print(__msg)\n"
        "return __msg\n"
    )


def _walk(obj):
    if isinstance(obj, dict):
        yield obj
        for v in obj.values():
            yield from _walk(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from _walk(v)


ID_KEYS = ("studio_id", "studioId", "id", "instance_id", "instanceId")
UUID_RE = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")


def parse_studios(result_text, structured=None):
    """list_roblox_studios output -> [{"id": str, "blob": str}] (blob = everything known about it, for matching)."""
    found = []
    docs = []
    if structured:
        docs.append(structured)
    try:
        docs.append(json.loads(result_text))
    except Exception:
        pass
    for doc in docs:
        for d in _walk(doc):
            for k in ID_KEYS:
                if k in d and isinstance(d[k], (str, int)) and str(d[k]):
                    found.append({"id": str(d[k]), "blob": json.dumps(d, sort_keys=True)})
                    break
        if found:
            break
    if not found and result_text:
        # Plain-text listing: one studio per line containing an id-looking token.
        for line in result_text.splitlines():
            m = UUID_RE.search(line)
            if m:
                found.append({"id": m.group(0), "blob": line.strip()})
    seen, out = set(), []
    for s in found:
        if s["id"] not in seen:
            seen.add(s["id"])
            out.append(s)
    return out


def pick_studio(studios, needles):
    """First studio whose blob contains one of `needles` (case-insensitive)."""
    for needle in needles:
        if not needle:
            continue
        for s in studios:
            if needle.lower() in s["blob"].lower():
                return s
    return None


# ---------------------------------------------------------------------------
# The session
# ---------------------------------------------------------------------------

class McpSession:
    """One StudioMCP.exe process + initialize handshake; tools/call helpers."""

    def __init__(self, exe, timeout=120, client_name="pc-watcher"):
        self.exe = exe
        self.timeout = timeout
        self.client_name = client_name
        self.p = None
        self.q = queue.Queue()
        self.err = []
        self._nid = 0
        self.schemas = {}
        self.server_info = None

    # --- process / transport ---
    def start(self):
        flags = 0x08000000 if os.name == "nt" else 0  # CREATE_NO_WINDOW
        self.p = subprocess.Popen(
            [self.exe],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=os.path.dirname(self.exe),
            bufsize=0,
            creationflags=flags,
        )
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()
        r = self.request(
            "initialize",
            {
                "protocolVersion": PROTO,
                "capabilities": {"roots": {}, "sampling": {}},
                "clientInfo": {"name": self.client_name, "version": "1.0.0"},
            },
            timeout=60,
        )
        if "error" in r:
            raise RuntimeError("initialize failed: %s" % (r["error"],))
        self.server_info = r.get("result", {}).get("serverInfo")
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        try:
            tl = self.request("tools/list", {}, timeout=30)
            for t in tl.get("result", {}).get("tools", []) or []:
                self.schemas[t.get("name")] = t.get("inputSchema") or {}
        except Exception as e:  # not fatal; we fall back to guessed shapes
            log.warning("tools/list failed: %r", e)
        log.info("MCP up: %s, %d tools", self.server_info, len(self.schemas))
        return self

    def alive(self):
        return self.p is not None and self.p.poll() is None

    def _read_stdout(self):
        for raw in self.p.stdout:
            line = raw.decode("utf-8", "replace").strip()
            if not line:
                continue
            try:
                self.q.put(json.loads(line))
            except Exception:
                self.err.append("NONJSON-OUT: " + line[:300])

    def _read_stderr(self):
        for raw in self.p.stderr:
            s = raw.decode("utf-8", "replace").rstrip()
            if s:
                self.err.append(s[:500])
                del self.err[:-200]

    def _send(self, obj):
        self.p.stdin.write((json.dumps(obj) + "\n").encode("utf-8"))
        self.p.stdin.flush()

    def request(self, method, params=None, timeout=None):
        self._nid += 1
        nid = self._nid
        msg = {"jsonrpc": "2.0", "id": nid, "method": method}
        if params is not None:
            msg["params"] = params
        self._send(msg)
        deadline = time.time() + (timeout or self.timeout)
        while time.time() < deadline:
            try:
                m = self.q.get(timeout=1.0)
            except queue.Empty:
                if self.p.poll() is not None:
                    raise RuntimeError("StudioMCP exited rc=%s stderr=%s" % (self.p.poll(), self.err[-5:]))
                continue
            if m.get("id") == nid:
                return m
            # Notifications and late replies to timed-out calls are dropped.
        raise TimeoutError("timeout after %ss on %s" % (timeout or self.timeout, method))

    def close(self):
        if not self.p:
            return
        try:
            self.p.stdin.close()
        except Exception:
            pass
        try:
            self.p.wait(timeout=5)
        except Exception:
            self.p.kill()

    # --- tools ---
    def call(self, tool, args=None, timeout=None):
        t0 = time.time()
        try:
            r = self.request("tools/call", {"name": tool, "arguments": args or {}}, timeout=timeout)
        except Exception as e:
            res = ToolResult(tool, error="DRIVER: %r" % (e,))
        else:
            res = ToolResult(tool, r["result"]) if "result" in r else ToolResult(tool, error=r.get("error"))
        log.debug("%s %s -> %.1fs %s", tool, _short_args(args), time.time() - t0, res.brief(200))
        return res

    def list_studios(self):
        r = self.call("list_roblox_studios", {}, timeout=30)
        return parse_studios(r.text, r.structured), r

    def luau(self, studio_id, body, datamodel="Edit", timeout=60):
        """Runs a Luau body (must `return` a JSON-able table). Returns (ok, data_or_error, ToolResult)."""
        nonce = uuid.uuid4().hex[:12]
        code = wrap_luau(body, nonce)
        r = self.call(
            "execute_luau",
            {"studio_id": studio_id, "code": code, "datamodel_type": datamodel},
            timeout=timeout,
        )
        payload = extract_marked(r.text, nonce)
        if payload is None and not r.error:
            con = self.call("get_console_output", {"studio_id": studio_id}, timeout=20)
            payload = extract_marked(con.text, nonce)
        if payload is None:
            return False, "no result (%s)" % r.brief(), r
        if not payload.get("ok"):
            return False, payload.get("error", "?"), r
        return True, payload.get("data"), r


def _short_args(args):
    s = json.dumps(args or {})
    return s if len(s) < 160 else s[:150] + "...(%d)" % len(s)
