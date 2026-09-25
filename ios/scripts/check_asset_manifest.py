#!/usr/bin/env python3
"""Fail CI when shipped image assets are unused, unexpected, or grow silently."""

from __future__ import annotations

import json
from pathlib import Path


IOS_ROOT = Path(__file__).resolve().parents[1]
CATALOG = IOS_ROOT / "QuitNic" / "Assets.xcassets"
MANIFEST = IOS_ROOT / "asset-manifest.json"
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png"}


def main() -> int:
    manifest = json.loads(MANIFEST.read_text())
    expected = manifest["assets"]
    actual = {
        path.relative_to(CATALOG).as_posix(): path.stat().st_size
        for path in CATALOG.rglob("*")
        if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES
    }
    errors: list[str] = []

    missing = sorted(set(expected) - set(actual))
    unexpected = sorted(set(actual) - set(expected))
    if missing:
        errors.append("missing assets: " + ", ".join(missing))
    if unexpected:
        errors.append("unmanifested assets: " + ", ".join(unexpected))

    for relative_path, size in actual.items():
        maximum = expected.get(relative_path)
        if maximum is not None and size > maximum:
            errors.append(f"{relative_path} is {size} bytes; budget is {maximum}")

    total = sum(actual.values())
    total_maximum = int(manifest["total_max_bytes"])
    if total > total_maximum:
        errors.append(f"image payload is {total} bytes; budget is {total_maximum}")

    swift_source = "\n".join(path.read_text() for path in (IOS_ROOT / "QuitNic").rglob("*.swift"))
    for imageset in sorted(CATALOG.glob("*.imageset")):
        asset_name = imageset.stem
        if f'"{asset_name}"' not in swift_source:
            errors.append(f"unused image set: {asset_name}")

    if errors:
        print("Asset manifest check failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print(f"Asset manifest OK: {len(actual)} images, {total}/{total_maximum} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
