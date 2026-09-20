#!/usr/bin/env bash
#
# check-browser-stack.sh — read-only health check of the browser/TLS stack on
# parmesan.local. Run from asiago. Modifies nothing on the target host.
#
# Exercises the distinction that matters on macOS 10.13: openssl/LibreSSL uses
# its own trust logic, while nscurl uses CFNetwork/SecureTransport — the same
# stack as Safari. Only the nscurl result says anything about OS trust.
#
# Remote script bodies are fed to ssh on stdin via quoted heredocs, so they are
# evaluated entirely on the target and never expanded locally.
#
# See docs/browser-diagnosis.md for the reasoning behind each probe.

set -euo pipefail

HOST="${PARMESAN_HOST:-andrewrich@parmesan.local}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)

# The SSH client warns about post-quantum key exchange against this old sshd.
# It is expected and not actionable, so filter it from output.
strip_pq_warning() {
  grep -v -E 'WARNING: connection is not using a post-quantum|store now, decrypt later|openssh\.com/pq' || true
}

# Reads the remote script from stdin. Callers use: remote <<'EOF' ... EOF
remote() {
  ssh "${SSH_OPTS[@]}" "$HOST" bash -s 2>&1 | strip_pq_warning
}

section() {
  printf '\n===== %s =====\n' "$1"
}

section "HOST"
remote <<'EOF'
hostname
sw_vers 2>/dev/null
sysctl -n hw.model machdep.cpu.brand_string hw.memsize 2>/dev/null
uptime
EOF

section "TRUST STORE (informational — frozen state is expected)"
remote <<'EOF'
ls -la /System/Library/Keychains/SystemRootCertificates.keychain
printf 'root count: '
security find-certificate -a /System/Library/Keychains/SystemRootCertificates.keychain 2>/dev/null | grep -c labl
EOF

section "OS TRUST PATH via nscurl (Safari stack — this is the one that counts)"
remote <<'EOF'
for u in https://www.cloudflare.com https://www.google.com; do
  printf '%-32s ' "$u"
  if /usr/bin/nscurl "$u" 2>&1 | head -c 200 | grep -qi '<!DOCTYPE\|<html'; then
    echo 'OK (HTML returned — TLS validates)'
  else
    echo 'FAIL (no HTML — investigate trust store)'
  fi
done
EOF

# Deliberately NOT probed here: fetching a Cloudflare-protected URL with curl
# and a spoofed Safari user agent. That probe returns an identical challenge
# from every machine, including fully patched ones, because Cloudflare scores
# the TLS fingerprint rather than the user agent string. It looks like a
# browser test and is not one. It misled this diagnosis once; see
# docs/browser-diagnosis.md, "How to test browser behaviour here, and how not
# to". The render test below is the real check.

section "CLOUDFLARE CLEARANCE (from the desktop profile, not a probe)"
remote <<'EOF'
# Cloudflare issues cf_clearance only after a challenge has been solved, so its
# presence in the real profile is evidence the browser clears challenges. This
# reads what ordinary browsing already produced; it drives nothing.
found=0
for p in "$HOME/Library/Application Support/Firefox/Profiles/"*/; do
  [ -f "$p/cookies.sqlite" ] || continue
  t=$(mktemp -d)
  cp "$p/cookies.sqlite" "$p/cookies.sqlite-wal" "$t/" 2>/dev/null
  n=$(/usr/bin/sqlite3 "$t/cookies.sqlite" \
        "select count(*) from moz_cookies where name='cf_clearance';" 2>/dev/null)
  rm -rf "$t"
  [ -n "$n" ] || n=0
  if [ "$n" -gt 0 ]; then
    printf '%-28s %s cf_clearance cookie(s) — challenges are being solved\n' "$(basename "$p")" "$n"
    found=1
  else
    printf '%-28s none\n' "$(basename "$p")"
  fi
done
if [ "$found" = "0" ]; then
  echo 'No clearance recorded. This is expected if the GUI has not visited a'
  echo 'challenged site yet; it is not by itself a failure.'
fi
EOF

section "BROWSERS INSTALLED"
remote <<'EOF'
printf 'Safari:  '
defaults read /Applications/Safari.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo absent
printf 'Firefox: '
defaults read /Applications/Firefox.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo absent
EOF

section "FIREFOX RENDER TEST"
remote <<'EOF'
if [ ! -x /Applications/Firefox.app/Contents/MacOS/firefox ]; then
  echo 'Firefox not installed — skipping'
  exit 0
fi

# Every launch gets its own throwaway profile, created inside attempt_shot and
# destroyed when it returns. Two reasons, both learned the hard way:
#
#   --no-remote plus a private profile stops this check attaching to whatever
#   Firefox the user has open on the desktop. Without it the check disturbs
#   their session and reports spurious FAILs.
#
#   A profile must not be REUSED between launches either. Reusing one directory
#   across URLs produced a reliable false FAIL on the second URL, while the same
#   URL passed in ~10s every time it was launched against a fresh profile.
#
# 10.13 has no timeout(1); poll a background pid instead.
attempt_shot() {
  url="$1"; lim="$2"; out="$3"
  rm -f "$out"
  profile=$(mktemp -d /tmp/_bstack_profile_XXXXXX)
  /Applications/Firefox.app/Contents/MacOS/firefox \
    --no-remote --profile "$profile" \
    --headless --screenshot "$out" "$url" >/dev/null 2>&1 &
  pid=$!
  n=0
  while kill -0 "$pid" 2>/dev/null && [ "$n" -lt "$lim" ]; do
    sleep 2
    n=$((n + 2))
  done
  kill -9 "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -rf "$profile"
  [ -s "$out" ]
}

# Cold start on this hardware routinely exceeds the first budget, so a single
# miss is not evidence of a broken page. Retry once with a longer budget and
# only report FAIL if both attempts come back empty.
run_shot() {
  url="$1"; out="/tmp/_bstack_$$.png"
  if attempt_shot "$url" 150 "$out"; then
    printf 'OK   %-32s %s\n' "$url" "$(ls -lh "$out" | awk '{print $5}')"
  elif attempt_shot "$url" 240 "$out"; then
    printf 'OK   %-32s %s (needed retry — cold start)\n' "$url" "$(ls -lh "$out" | awk '{print $5}')"
  else
    printf 'FAIL %-32s (two attempts, 150s then 240s)\n' "$url"
  fi
  rm -f "$out"
}
run_shot 'https://claude.ai'
run_shot 'https://www.cloudflare.com'
EOF

section "FIREFOX ESR 115 UPDATE CHECK"
installed=$(
  remote <<'EOF' | tr -d '[:space:]'
defaults read /Applications/Firefox.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null
EOF
)
latest=$(curl -sS https://product-details.mozilla.org/1.0/firefox_versions.json 2>/dev/null \
  | grep -o '"FIREFOX_ESR115": *"[^"]*"' | cut -d'"' -f4 | sed 's/esr$//')
printf 'installed: %s\n' "${installed:-absent}"
printf 'latest:    %s\n' "${latest:-unknown}"
if [ -n "$installed" ] && [ -n "$latest" ]; then
  if [ "$installed" = "$latest" ]; then
    echo 'up to date'
  else
    echo 'UPDATE AVAILABLE — see scripts/install-firefox-esr.sh'
  fi
fi

printf '\nDone.\n'
