#!/usr/bin/env bash
# Push the latest main branch to GitHub (yukyiuwan-png/siftroll-ios-app).
# Run on your Mac where `gh auth login` or GitHub HTTPS credentials work.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GITHUB_REPO="${GITHUB_REPO:-https://github.com/yukyiuwan-png/siftroll-ios-app.git}"

if ! git remote | grep -qx github; then
  git remote add github "$GITHUB_REPO"
  echo "Added remote github → $GITHUB_REPO"
fi

git fetch origin main
git fetch github main 2>/dev/null || true

git checkout main
git pull --rebase origin main

AHEAD="$(git rev-list --count github/main..main 2>/dev/null || echo '?')"
echo "Commits on main not yet on GitHub: $AHEAD"

git push -u github main
echo "Done. GitHub main is now at $(git rev-parse --short HEAD)."
