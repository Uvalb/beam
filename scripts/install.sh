#!/usr/bin/env bash
# Build Beam and install it to /Applications, then launch it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="/Applications/Beam.app"

cd "$ROOT"

if [ ! -w /Applications ]; then
  echo "error: /Applications is not writable by $(whoami)." >&2
  echo "Fix permissions, or install manually:" >&2
  echo "  make app && sudo rm -rf $DEST && sudo cp -R build/Beam.app $DEST" >&2
  exit 1
fi

echo "==> Building Beam.app (release)"
make app

echo "==> Quitting running Beam (if any)"
pkill -x Beam || true
sleep 1

echo "==> Installing to $DEST"
rm -rf "$DEST"
cp -R build/Beam.app "$DEST"

echo "==> Launching"
open "$DEST"

echo "Done. Beam is installed at $DEST"
