#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 Scripts/verify_xcode_project.py
dup_names=$(find SiftRoll -name '*.swift' -exec basename {} \; | sort | uniq -d || true)
if [[ -n "$dup_names" ]]; then
  echo "warning: duplicate Swift filenames under SiftRoll/ (often a nested clone):"
  echo "$dup_names"
  find SiftRoll -name 'AssetThumbnailView.swift' -o -name 'PhotoLibraryService.swift'
fi
