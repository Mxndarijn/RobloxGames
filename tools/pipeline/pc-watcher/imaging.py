"""Pure image helpers: PNG encode/decode (zlib only), blank-frame check, JPEG via Pillow.

No Windows APIs here, so selftest.py can run it anywhere.
Pixel buffers are (width, height, mode, bytes) with mode "RGB" or "RGBA", rows top-down.
"""

import struct
import zlib

try:  # optional
    from PIL import Image  # type: ignore
except Exception:  # pragma: no cover - Pillow missing is a normal case
    Image = None


def have_pillow():
    return Image is not None


def bgra_to_rgb(width, height, bgra, bottom_up=False):
    """Converts a 32-bit BGRA/BGRX DIB buffer to packed RGB rows (top-down)."""
    stride = width * 4
    out = bytearray(width * height * 3)
    for y in range(height):
        src_y = (height - 1 - y) if bottom_up else y
        row = bgra[src_y * stride:(src_y + 1) * stride]
        o = y * width * 3
        out[o + 0:o + width * 3:3] = row[2::4]
        out[o + 1:o + width * 3:3] = row[1::4]
        out[o + 2:o + width * 3:3] = row[0::4]
    return bytes(out)


def _chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def encode_png(width, height, rgb, mode="RGB"):
    channels = 4 if mode == "RGBA" else 3
    stride = width * channels
    if len(rgb) != stride * height:
        raise ValueError("pixel buffer is %d bytes, expected %d" % (len(rgb), stride * height))
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: none
        raw += rgb[y * stride:(y + 1) * stride]
    color_type = 6 if channels == 4 else 2
    ihdr = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(bytes(raw), 6))
        + _chunk(b"IEND", b"")
    )


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def decode_png(data):
    """Decodes 8-bit RGB / RGBA, non-interlaced PNGs (what Studio and encode_png write).

    Returns (width, height, mode, bytes) or raises ValueError for anything else.
    """
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, ihdr = 8, bytearray(), None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    if ihdr is None:
        raise ValueError("no IHDR")
    width, height, depth, color_type, _, _, interlace = ihdr
    if depth != 8 or color_type not in (2, 6) or interlace != 0:
        raise ValueError("unsupported PNG (depth %d, color %d, interlace %d)" % (depth, color_type, interlace))
    bpp = 3 if color_type == 2 else 4
    stride = width * bpp
    raw = zlib.decompress(bytes(idat))
    out = bytearray(stride * height)
    prev = bytearray(stride)
    i = 0
    for y in range(height):
        ftype = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if ftype == 1:
                line[x] = (line[x] + a) & 0xFF
            elif ftype == 2:
                line[x] = (line[x] + b) & 0xFF
            elif ftype == 3:
                line[x] = (line[x] + ((a + b) >> 1)) & 0xFF
            elif ftype == 4:
                line[x] = (line[x] + _paeth(a, b, c)) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, ("RGB" if bpp == 3 else "RGBA"), bytes(out)


def frame_stats(width, height, pixels, mode="RGB", samples=4096):
    """Luma mean / variance / distinct-colour count over an even sample grid."""
    channels = 4 if mode == "RGBA" else 3
    if width <= 0 or height <= 0:
        return {"mean": 0.0, "variance": 0.0, "distinct": 0, "samples": 0}
    step = max(1, int(((width * height) / samples) ** 0.5))
    lumas, colours = [], set()
    for y in range(0, height, step):
        base = y * width * channels
        for x in range(0, width, step):
            o = base + x * channels
            r, g, b = pixels[o], pixels[o + 1], pixels[o + 2]
            lumas.append(0.299 * r + 0.587 * g + 0.114 * b)
            colours.add((r >> 3, g >> 3, b >> 3))
    n = len(lumas)
    mean = sum(lumas) / n
    var = sum((v - mean) ** 2 for v in lumas) / n
    return {"mean": round(mean, 2), "variance": round(var, 2), "distinct": len(colours), "samples": n}


def is_blank(stats, min_variance=40.0, min_distinct=12):
    """A frame is blank when it is (nearly) one flat colour: black, white or a loading grey."""
    return stats["variance"] < min_variance or stats["distinct"] < min_distinct


def save_png(path, width, height, pixels, mode="RGB"):
    with open(path, "wb") as f:
        f.write(encode_png(width, height, pixels, mode))


def to_jpeg(src_png, dst_jpg, quality=80):
    """PNG -> JPEG with Pillow. Returns False (and writes nothing) without Pillow."""
    if Image is None:
        return False
    with Image.open(src_png) as im:
        im.convert("RGB").save(dst_jpg, "JPEG", quality=quality, optimize=True)
    return True


def jpeg_stats(data):
    """frame_stats of JPEG bytes (Pillow) plus w/h, or None without Pillow / on undecodable data."""
    if Image is None:
        return None
    import io
    try:
        with Image.open(io.BytesIO(data)) as im:
            rgb = im.convert("RGB")
            st = frame_stats(rgb.width, rgb.height, rgb.tobytes())
            st.update(w=rgb.width, h=rgb.height)
            return st
    except Exception:
        return None


def crop_rgb(width, height, rgb, x, y, w, h):
    """Packed RGB rows -> (w, h, rgb) of the rect clamped to the image."""
    x0, y0 = max(0, int(x)), max(0, int(y))
    x1, y1 = min(width, int(x) + int(w)), min(height, int(y) + int(h))
    if x1 <= x0 or y1 <= y0:
        raise ValueError("crop %r outside %dx%d" % ((x, y, w, h), width, height))
    out = bytearray()
    for row in range(y0, y1):
        o = (row * width + x0) * 3
        out += rgb[o:o + (x1 - x0) * 3]
    return x1 - x0, y1 - y0, bytes(out)


def _row_span(row, colour, tol):
    """(first, last) pixel index in one packed RGB row within `tol` of `colour`, or None."""
    if tol == 0:
        needle = bytes(colour)
        i = row.find(needle)
        while i != -1 and i % 3:
            i = row.find(needle, i + 1)
        if i == -1:
            return None
        j = row.rfind(needle)
        while j != -1 and j % 3:
            j = row.rfind(needle, 0, j + 2)
        return i // 3, j // 3
    r0, g0, b0 = colour
    hits = [i for i in range(0, len(row), 3)
            if abs(row[i] - r0) <= tol and abs(row[i + 1] - g0) <= tol and abs(row[i + 2] - b0) <= tol]
    return (hits[0] // 3, hits[-1] // 3) if hits else None


def find_colour_rect(width, height, rgb, colour=(255, 0, 255), tol=0, min_fill=0.8):
    """Bounding rect (x, y, w, h) of a flat `colour` region, e.g. a full-screen probe frame.

    Exact match first, then `tol` (slow pure-Python path). None when absent or when the colour
    covers less than `min_fill` of its rect on a sample grid (a stray pixel, not a probe).
    """
    for t in ([0] if tol == 0 else [0, tol]):
        rows = []
        for y in range(height):
            span = _row_span(rgb[y * width * 3:(y + 1) * width * 3], colour, t)
            if span:
                rows.append((y, span))
        if not rows:
            continue
        x0 = min(s[0] for _, s in rows)
        x1 = max(s[1] for _, s in rows)
        y0, y1 = rows[0][0], rows[-1][0]
        rect = (x0, y0, x1 - x0 + 1, y1 - y0 + 1)
        if _fill(width, rgb, rect, colour, max(t, 8)) >= min_fill:
            return rect
    return None


def _fill(width, rgb, rect, colour, tol, grid=24):
    x, y, w, h = rect
    hit = n = 0
    for gy in range(grid):
        for gx in range(grid):
            o = ((y + gy * h // grid) * width + x + gx * w // grid) * 3
            n += 1
            hit += all(abs(rgb[o + c] - colour[c]) <= tol for c in range(3))
    return hit / float(n)
