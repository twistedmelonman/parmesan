#!/usr/bin/env bash
#
# install-firefox-esr.sh — install or update Firefox 115 ESR on parmesan.local.
# Run from asiago. Requires passwordless ssh + passwordless sudo on the target.
#
# Firefox 115 ESR is the last branch supporting macOS 10.12-10.14 and still
# receives security updates. It carries its own NSS root store, so it does not
# depend on the target's frozen system keychain.
#
# The download is verified against Mozilla's published SHA256SUMS before
# anything is installed. A checksum mismatch aborts the run and removes the
# downloaded file.
#
# Remote script bodies are fed to ssh on stdin. Values the remote side needs
# are passed as positional arguments to `bash -s`, never interpolated into the
# script text.

set -euo pipefail

HOST="${PARMESAN_HOST:-andrewrich@parmesan.local}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)
PRODUCT='firefox-esr115-latest-ssl'
DMG_REMOTE='/tmp/firefox-esr115.dmg'

strip_pq_warning() {
  grep -v -E 'WARNING: connection is not using a post-quantum|store now, decrypt later|openssh\.com/pq' || true
}

# Reads the remote script from stdin; any extra args become $1, $2 ... remotely.
remote() {
  ssh "${SSH_OPTS[@]}" "$HOST" bash -s -- "$@" 2>&1 | strip_pq_warning
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

echo '1. Resolving current ESR 115 version'
version=$(curl -sS https://product-details.mozilla.org/1.0/firefox_versions.json \
  | grep -o '"FIREFOX_ESR115": *"[^"]*"' | cut -d'"' -f4)
[ -n "$version" ] || die 'could not resolve FIREFOX_ESR115 version'
printf '   version: %s\n' "$version"

echo '2. Fetching official checksum'
want=$(curl -sS "https://download-installer.cdn.mozilla.net/pub/firefox/releases/${version}/SHA256SUMS" \
  | grep "mac/en-US/Firefox ${version}.dmg" | awk '{print $1}')
[ -n "$want" ] || die "could not fetch published SHA256 for ${version}"
printf '   sha256: %s\n' "$want"

echo '3. Downloading to target'
remote "$DMG_REMOTE" "$PRODUCT" <<'EOF'
dmg="$1"
product="$2"
curl -sSL -o "$dmg" "https://download.mozilla.org/?product=${product}&os=osx&lang=en-US"
EOF

echo '4. Verifying checksum on target'
got=$(
  remote "$DMG_REMOTE" <<'EOF' | awk '{print $1}'
shasum -a 256 "$1"
EOF
)
printf '   got:    %s\n' "$got"
if [ "$got" != "$want" ]; then
  remote "$DMG_REMOTE" <<'EOF'
rm -f "$1"
EOF
  die 'checksum mismatch — download discarded, nothing installed'
fi
echo '   match confirmed'

echo '5. Installing to /Applications'
# No sudo here, deliberately. /Applications is root:admin 775 and the install
# account is in admin, so an ordinary copy succeeds. Installing with sudo
# leaves the bundle root-owned, which breaks Firefox's in-app updater for ESR
# point releases.
remote "$DMG_REMOTE" <<'EOF'
set -e
dmg="$1"
hdiutil attach "$dmg" -nobrowse -quiet
mp=$(ls -d /Volumes/Firefox* 2>/dev/null | head -1)
if [ -z "$mp" ]; then
  echo 'mount failed'
  exit 1
fi
# Remove any prior copy so a downgrade or repair lands cleanly.
rm -rf /Applications/Firefox.app
cp -R "$mp/Firefox.app" /Applications/
hdiutil detach "$mp" -quiet
xattr -dr com.apple.quarantine /Applications/Firefox.app
rm -f "$dmg"
EOF

echo '   confirming ownership'
remote <<'EOF'
owner=$(stat -f '%Su:%Sg' /Applications/Firefox.app)
stray=$(find /Applications/Firefox.app -user root 2>/dev/null | wc -l | tr -d ' ')
printf '   owner: %s, root-owned files: %s\n' "$owner" "$stray"
if [ "$stray" != "0" ]; then
  echo '   WARNING: root-owned files present — in-app updates will fail'
  echo '   fix: sudo chown -R "$(id -un):staff" /Applications/Firefox.app'
fi
EOF

echo '6. Verifying install'
got_ver=$(
  remote <<'EOF' | tr -d '[:space:]'
defaults read /Applications/Firefox.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null
EOF
)
printf '   installed: %s\n' "${got_ver:-absent}"
[ -n "$got_ver" ] || die 'install verification failed'

printf '\nDone. Run scripts/check-browser-stack.sh to confirm rendering.\n'
