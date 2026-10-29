"""The Open Cloud API key from the env or ~/.config/roblox-ci.env. Never printed."""
import os, sys


def key():
    k = os.environ.get("ROBLOX_OPEN_CLOUD_API_KEY")
    if k:
        return k
    path = os.path.expanduser("~/.config/roblox-ci.env")
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line.startswith("export "):
            line = line[7:]
        if line.startswith("ROBLOX_OPEN_CLOUD_API_KEY="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    sys.exit("no key")
