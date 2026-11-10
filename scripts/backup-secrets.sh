#!/bin/bash
# Collects Beam's irreplaceable signing secrets into one folder for you to encrypt and back up.
# Run it in your own terminal (macOS will ask for Keychain access and a .p12 passphrase).
#   usage: scripts/backup-secrets.sh [destination folder]   (default: ~/beam-secrets-backup)
# The output contains private keys: never put it in a git repo or cloud folder unencrypted.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="${1:-$HOME/beam-secrets-backup}"
SIGN_ID="${SIGN_ID:-Developer ID Application: Uval Blumenfeld (P9GCM9K6AH)}"
mkdir -p "$DEST"; chmod 700 "$DEST"

echo "==> Sparkle EdDSA private key"
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x "$DEST/sparkle-ed25519-private.key"
chmod 600 "$DEST/sparkle-ed25519-private.key"

echo "==> Developer ID certificate + private key"
read -r -s -p "Passphrase for the .p12 (remember it, store it separately): " PASS; echo
security find-identity -v -p codesigning | grep -qF "$SIGN_ID" || { echo "Identity not found: $SIGN_ID" >&2; exit 1; }
# security(1) cannot export a single identity: this exports every identity in the login keychain.
echo "Note: this exports EVERY identity in your login keychain, not only Beam's Developer ID."
security export -k login.keychain-db -t identities -f pkcs12 -P "$PASS" -o "$DEST/developer-id.p12"
chmod 600 "$DEST/developer-id.p12"

cat > "$DEST/README.txt" <<N
Beam secrets backup, $(date +%F)
- sparkle-ed25519-private.key: restore with  generate_keys -f <file>  (needed to ship updates to existing installs)
- developer-id.p12: all identities in the login keychain, including the Developer ID Application cert + key. Import by double-clicking.
- Not exportable: the notarytool app-specific password. Recreate at appleid.apple.com, then
  xcrun notarytool store-credentials beam-notary --apple-id <apple id> --team-id P9GCM9K6AH
- Also keep: Apple ID, Lemon Squeezy login, and a remote/backup of ../beam-private.
N
echo "Done: $DEST  (now encrypt this folder, e.g. an encrypted disk image, and delete the plaintext)"
