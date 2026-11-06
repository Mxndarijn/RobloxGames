"""The Steal a Slime universe and the Open Cloud API key (env or ~/.config/roblox-ci.env; never printed)."""
import os, sys

# The experience every monetization script talks to. The game moved here on 2026-11-06 (docs/release-pipeline.md);
# the old universe 10770917350's ids are kept in created_ids.old-10770917350.json.
UNIVERSE = "10774962286"
PLACE = "105898249206841"


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
