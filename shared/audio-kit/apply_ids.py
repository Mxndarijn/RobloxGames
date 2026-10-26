"""Copy uploaded asset ids from manifest.json into a game's sound registry.

Each manifest entry may list `uses`: { "<path to a Sounds.luau, from the repo root>": ["<Sounds.IDS name>", ...] }.
For every entry with an assetId, each named line `\t<Name> = "",` in that file becomes
`\t<Name> = "rbxassetid://<id>",` (the comment after it stays). Lines that already hold an id are left alone unless
--force. Dry run by default; --write saves the files.

    python shared/audio-kit/apply_ids.py           # show what would change
    python shared/audio-kit/apply_ids.py --write
"""

import argparse
import json
import re
from pathlib import Path

KIT = Path(__file__).resolve().parent
REPO = KIT.parent.parent


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true", help="save the changed files")
    ap.add_argument("--force", action="store_true", help="also replace ids that are already set")
    args = ap.parse_args()

    manifest = json.loads((KIT / "manifest.json").read_text(encoding="utf-8"))
    edits: dict[Path, list[tuple[str, str]]] = {}
    for entry in manifest["sounds"]:
        asset = str(entry.get("assetId") or "")
        for path, names in (entry.get("uses") or {}).items():
            for name in names:
                edits.setdefault(REPO / path, []).append((name, asset))

    for path, pairs in edits.items():
        text = path.read_bytes().decode("utf-8")
        changed = text
        for name, asset in pairs:
            current = re.search(rf'^\t{re.escape(name)} = "([^"]*)",', changed, re.M)
            if not current:
                print(f"MISSING  {path.relative_to(REPO)}: no line for {name}")
                continue
            if not asset:
                print(f"waiting  {name}: not uploaded yet")
                continue
            if current.group(1) and not args.force:
                print(f"kept     {name} = {current.group(1)}")
                continue
            changed = changed[: current.start(1)] + f"rbxassetid://{asset}" + changed[current.end(1) :]
            print(f"set      {name} = rbxassetid://{asset}")
        if changed != text and args.write:
            path.write_bytes(changed.encode("utf-8"))  # bytes: keeps LF line endings on Windows
    if not args.write:
        print("(dry run: pass --write to save)")


if __name__ == "__main__":
    main()
