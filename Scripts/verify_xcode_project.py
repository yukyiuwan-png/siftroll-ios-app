#!/usr/bin/env python3
"""Verify SiftRoll.xcodeproj lists each Swift file once in Compile Sources."""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PBX = ROOT / "SiftRoll.xcodeproj" / "project.pbxproj"


def main() -> int:
    pbx = PBX.read_text(encoding="utf-8")
    if "PBXFileSystemSynchronizedRootGroup" in pbx:
        print("error: synchronized root folder can duplicate Compile Sources")
        return 1

    file_refs = {
        m[0]: m[2]
        for m in re.findall(
            r"\t\t([0-9A-F]+) /\* ([^*]+) \*/ = \{isa = PBXFileReference; "
            r'lastKnownFileType = sourcecode\.swift; path = "([^"]+)";',
            pbx,
        )
    }
    build_to_ref = {
        m[0]: m[1]
        for m in re.findall(
            r"\t\t([0-9A-F]+) /\* .+ in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([0-9A-F]+)",
            pbx,
        )
    }
    sources_block = re.search(
        r"/\* Begin PBXSourcesBuildPhase section \*/.*?/\* End PBXSourcesBuildPhase section \*/",
        pbx,
        re.S,
    )
    if not sources_block:
        print("error: no PBXSourcesBuildPhase found")
        return 1

    build_ids = re.findall(
        r"^\s+([0-9A-F]+) /\* .+ in Sources \*/,\s*$",
        sources_block.group(0),
        re.M,
    )
    paths = [
        file_refs[build_to_ref[b]]
        for b in build_ids
        if b in build_to_ref and build_to_ref[b] in file_refs
    ]
    dupes = sorted({p for p in paths if paths.count(p) > 1})
    if dupes:
        print("error: duplicate Compile Sources entries:")
        for p in dupes:
            print(" ", p)
        return 1

    print(f"ok: {len(paths)} Swift files, each listed once in Compile Sources")
    return 0


if __name__ == "__main__":
    sys.exit(main())
