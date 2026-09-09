#!/bin/bash
# Cuts a release: bumps VERSION, builds + tests + packages, commits, tags, pushes, and publishes a
# GitHub release with the zip. Installed copies of Tide pick it up through Check for Updates.
#   tools/release.sh 1.0.1 "What changed"
set -euo pipefail
cd "$(dirname "$0")/.."
NEW="${1:?usage: tools/release.sh <version> [notes]}"
NOTES="${2:-}"
[[ "$NEW" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo "version must look like 1.2.3"; exit 1; }
if git rev-parse "v$NEW" >/dev/null 2>&1; then echo "tag v$NEW already exists"; exit 1; fi

echo "$NEW" > VERSION
if [ -n "$NOTES" ]; then
  tmp=$(mktemp)
  { echo "# Changelog"; echo; echo "## $NEW — $(date +%Y-%m-%d)"; echo; echo "$NOTES"; echo; tail -n +2 CHANGELOG.md; } > "$tmp"
  mv "$tmp" CHANGELOG.md
fi

./build.sh --install --test --package

git add -A
git commit -m "Release $NEW" || true
git tag -a "v$NEW" -m "Tide $NEW"
git push origin HEAD
git push origin "v$NEW"

notes_file=$(mktemp)
python3 tools/notes.py "$NEW" > "$notes_file"
gh release create "v$NEW" "build.nosync/dist/Tide-$NEW.zip" --title "Tide $NEW" --notes-file "$notes_file"
echo "==> released Tide $NEW: $(gh release view "v$NEW" --json url --jq .url)"
