#!/usr/bin/env bash
# Quit Beam and remove it from /Applications.
set -euo pipefail

DEST="/Applications/Beam.app"

echo "==> Quitting running Beam (if any)"
pkill -x Beam || true

if [ -e "$DEST" ]; then
  if [ ! -w /Applications ]; then
    echo "error: /Applications is not writable by $(whoami)." >&2
    echo "Remove manually: sudo rm -rf $DEST" >&2
    exit 1
  fi
  echo "==> Removing $DEST"
  rm -rf "$DEST"
else
  echo "==> $DEST not present, nothing to remove"
fi

echo "Done. The launch-at-login entry goes stale once the app is removed;"
echo "if it still shows in System Settings > General > Login Items, remove it there."
