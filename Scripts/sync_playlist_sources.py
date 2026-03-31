#!/usr/bin/env python3

from __future__ import annotations

import shutil
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BRAVE_CORE_ROOT = REPO_ROOT.parent / "brave-core" / "ios" / "brave-ios" / "Sources" / "Brave" / "Frontend"
DESTINATION_ROOT = REPO_ROOT / "Sources" / "BravePlaylist" / "Resources"

SOURCE_MAP = {
    DEFAULT_BRAVE_CORE_ROOT / "UserContent" / "UserScripts" / "__firefox__.js":
        DESTINATION_ROOT / "UserScripts" / "__firefox__.js",
    DEFAULT_BRAVE_CORE_ROOT / "UserContent" / "UserScripts" / "Scripts_Dynamic" / "Scripts" / "Paged" / "PlaylistScript.js":
        DESTINATION_ROOT / "UserScripts" / "PlaylistScript.js",
    DEFAULT_BRAVE_CORE_ROOT / "UserContent" / "UserScripts" / "Scripts_Dynamic" / "Scripts" / "Paged" / "PlaylistSwizzlerScript.js":
        DESTINATION_ROOT / "UserScripts" / "PlaylistSwizzlerScript.js",
}


def main() -> int:
    missing = [path for path in SOURCE_MAP if not path.exists()]
    if missing:
        print("Missing Brave sources:", file=sys.stderr)
        for path in missing:
            print(f"  {path}", file=sys.stderr)
        return 1

    for source, destination in SOURCE_MAP.items():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        print(f"synced {source} -> {destination}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
