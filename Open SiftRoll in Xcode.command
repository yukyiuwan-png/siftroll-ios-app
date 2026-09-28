#!/bin/bash
# Double-click this file in Finder to open the Xcode project.
# The .xcodeproj must sit next to this script at the repository root.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/SiftRoll.xcodeproj"
if [[ ! -d "$PROJECT" ]]; then
  osascript -e "display alert \"SiftRoll.xcodeproj not found\" message \"Expected at:\\n$PROJECT\\n\\nRun: cd to your siftroll clone root, then git pull origin main\" as critical"
  exit 1
fi
open "$PROJECT"
