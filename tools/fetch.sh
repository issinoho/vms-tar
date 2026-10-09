#!/usr/bin/env bash
# fetch.sh - download the upstream release tarball named in upstream.conf into cache/
# and verify its SHA-256 and its GPG signature against keys/$UPSTREAM_NAME-signing-key.asc.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
. "$top/upstream.conf"

cache=$top/cache
mkdir -p "$cache"
tarball=$cache/$(basename "$UPSTREAM_URL")

if [ ! -f "$tarball" ]; then
    echo "fetch: downloading $UPSTREAM_URL"
    curl -fsSL -o "$tarball.tmp" "$UPSTREAM_URL"
    mv "$tarball.tmp" "$tarball"
fi
[ -f "$tarball.sig" ] || curl -fsSL -o "$tarball.sig" "$UPSTREAM_URL.sig"

echo "$UPSTREAM_SHA256  $tarball" | sha256sum -c --quiet - ||
    { echo "fetch: SHA-256 mismatch for $tarball" >&2; exit 1; }

# Verify against the pinned key in keys/ only (a throwaway keyring).  The
# primary key's fingerprint ends the VALIDSIG line; gpg reports VALIDSIG for a
# signature made while the key was valid even if it has expired since.
keyring=$cache/$UPSTREAM_NAME-keyring.gpg
rm -f "$keyring"
gpg --no-default-keyring --keyring "$keyring" --import "$top/keys/$UPSTREAM_NAME-signing-key.asc" 2>/dev/null
status=$(gpg --no-default-keyring --keyring "$keyring" --status-fd 1 \
             --verify "$tarball.sig" "$tarball" 2>/dev/null || true)
echo "$status" | grep -q "^\[GNUPG:\] VALIDSIG .* $UPSTREAM_GPG_KEY\$" ||
    { echo "fetch: GPG signature by $UPSTREAM_GPG_KEY not valid for $tarball" >&2; exit 1; }
echo "fetch: signature OK ($UPSTREAM_GPG_KEY)"
echo "fetch: $tarball"

