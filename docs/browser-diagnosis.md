# parmesan.local — web browsing diagnosis

Date: 2026-09-19
Host: parmesan.local (10.0.15.38), iMac12,1, Core i5-2400S, 4 GB RAM, macOS 10.13.6 (17G14042)

## Summary

Browsing failures on this machine were **not** caused by an expired or missing
certificate chain. The OS trust store validates modern sites correctly — this
is tested and confirmed below.

The cause is **Safari 13.1.2**, the last Safari release for High Sierra and now
roughly six years of WebKit behind current. It cannot be updated on this OS.
Safari reaches sites normally and then fails to execute their JavaScript, so
pages arrive and stay blank.

Fix: install Firefox 115 ESR, the long-term support branch Mozilla still
maintains for macOS 10.12–10.14. It renders every site tested.

### Confidence

Proven:

- The OS trust store validates modern TLS correctly (`nscurl` test below).
- Safari on this machine is 13.1.2 and cannot be upgraded.
- Safari reaches claude.ai and receives the real page. It is **not** blocked by
  Cloudflare and does **not** get a challenge. It fails while executing the
  page's JavaScript. Proven by a side-by-side capture from the console; see
  "What Safari actually does".
- Firefox 115.41.0esr renders modern JavaScript-heavy sites that Safari cannot
  display at all, including claude.ai, github.com and wikipedia.org.

- Firefox 115 ESR completes Cloudflare challenges on this host. It holds a
  `cf_clearance` cookie for claude.ai and a solved JavaScript-challenge
  redirect for reddit.com, and it loads the interstitial-protected page that
  was reported as stalling.

No open questions remain about the browsing failure or its fix.

## Evidence

### The certificate theory was tested and rejected

The system root keychain is frozen at its January 2020 state:

    /System/Library/Keychains/SystemRootCertificates.keychain   Jan 18 2020, 169 roots

`openssl s_client` reports `unable to get local issuer certificate` for several
modern roots (GTS Root R1/R4, ISRG Root X2, Sectigo E46, SSL.com 2022). This
looks damning but is misleading: the bundled LibreSSL 2.2.7 has its own trust
logic and is not what Safari uses.

The decisive test is `nscurl`, which uses CFNetwork/SecureTransport — the same
stack as Safari:

    /usr/bin/nscurl https://www.cloudflare.com   -> full HTML returned
    /usr/bin/nscurl https://www.google.com       -> full HTML returned

TLS negotiates and validates at the OS layer. Path building succeeds via
cross-signed intermediates that chain to roots already present. Certificates
are not the problem.

Note: `ISRG Root X1` and `DST Root CA X3` are both present, so the well-known
2021 Let's Encrypt expiry is not implicated either.

### Prior remediation attempts (do not repeat)

`~/Downloads` on the host holds the remains of an earlier, reasonable attempt
at the certificate theory:

- `cacert.pem` — the full Mozilla CA bundle
- `ISRG Root X1.der` — the Let's Encrypt root, fetched individually
- `trustroot.sh` — a script that splits a PEM bundle and runs
  `security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain`
  on each certificate

The approach was sound for the theory being tested, and MacPorts'
`apple-pki-bundle` is installed for the same reason. None of it helped, and the
`nscurl` result above explains why: the OS trust path was never broken, so
adding roots fixed a problem that did not exist.

Leave these files alone or delete them, but do not build on them. Importing
more roots will not improve browsing here.

### The browser is the remaining variable

Safari is version 13.1.2 — terminal for this OS, released 2020. The web has
moved roughly six years since, and Safari here cannot follow.

The previously installed alternative was `w3m` (MacPorts), a terminal browser
with no JavaScript at all. It could not have helped with modern sites.

### A probe that is easy to misread

Requesting claude.ai with a Safari 13.1 user agent returns a Cloudflare
challenge:

    https://claude.ai           ->  HTTP/2 403, cf-mitigated: challenge
    https://www.cloudflare.com  ->  HTTP/2 200

**This says nothing about Safari, and reading it as a diagnosis is a mistake
this document made before it was corrected.** The request came from `curl`
carrying a spoofed user agent. Cloudflare's bot detection reads the TLS
fingerprint (JA3/JA4), and a curl fingerprint claiming to be Safari is a
textbook bot signature. The second line makes the point: the same user agent
gets a clean 200 from cloudflare.com, so the challenge tracks per-site bot
rules and the client fingerprint, not the claimed browser version.

The capture below shows what really happens, and it is not this.

### What Safari actually does

Both browsers loaded `https://claude.ai/login` from the console and saved the
result — Safari as a `.webarchive`, Firefox as "save page complete". Comparing
them settles the question:

| Measure                    | Safari 13.1.2 | Firefox 115 ESR |
|----------------------------|---------------|-----------------|
| Page served by origin      | yes, 121 KB   | yes, 371 KB     |
| `challenge-platform` script| present       | present         |
| Subresources fetched       | 7             | 16              |
| Application JS bundles     | 1             | several         |
| Login form rendered        | **no**        | yes             |
| Hero video fetched         | no            | yes             |

Safari is **not blocked**. Cloudflare serves it the genuine page, including the
same `challenge-platform` script Firefox receives. There is no `403`, no
"Checking your browser", no "Just a moment", no captcha wall, and no `noscript`
fallback in what Safari stored.

Safari fetches the CSS and the web fonts, loads one JavaScript file, and stops.
None of the interface appears: no "Continue with Google", no "Continue with
Apple", no email field. Firefox, given the identical page, fetches the
application bundle (`index-qLs60Uv4.js`), the site's own hCaptcha frames and
the hero video, and builds the complete UI. (The hCaptcha frames belong to the
site's login form, not to Cloudflare, whose own captcha product is Turnstile.)

The failure is therefore in **JavaScript execution**, not in the network, not
in TLS, and not in bot mitigation. Safari 13's JavaScriptCore is from 2020;
current application bundles use syntax and APIs it does not implement, so the
bundle throws and the page stays blank. A blank page is exactly what "the page
won't open" looks like from the user's side.

This also explains the breadth of the symptom. Any site that renders its
interface client-side fails, while simple server-rendered pages still work —
which matches "most pages don't work" better than a certificate fault ever did.

### Archive mirrors work in Safari, and confirm the diagnosis

An independent confirmation, found by the operator before this diagnosis was
written: **`archive.today` and its mirrors (`archive.vn`, `archive.ph`) render
correctly in Safari 13.1.2 on this machine**, including pages that fail on
their original domains.

This is not a coincidence, and it is not a workaround that happens to help. It
is the prediction above, confirmed. An archive mirror serves a static
server-rendered snapshot: no Cloudflare interstitial to clear, and effectively
no application JavaScript to execute. It exercises only the parts of the stack
that work here, and avoids the one part that does not.

The comparison was run accidentally and is worth keeping. At 16:23 on
2026-09-19 a single Safari window held both of these at once:

| Tab | URL | State |
|---|---|---|
| Live original | `apple.stackexchange.com/questions/422332` | `Just a moment...`, retrying every ~32s |
| Archive mirror | `archive.vn/ke6YJ` — the same article | rendered, readable |

Same browser, same machine, same moment, same article. One is stuck at
Cloudflare's door; the other is open and readable. If the fault were TLS, the
trust store, or the network, the mirror would fail too.

Three independent lines of evidence agree:

1. The operator read these pages in Safari when the originals would not open.
2. Safari's history stores real article titles for the mirrors — `network - Set
   the hostname/computer name for macOS - Ask Different` — where challenged
   pages store only `Just a moment...`. A title is proof the document parsed.
3. `nscurl https://archive.vn/...` returns HTML, so the mirror validates
   through CFNetwork/SecureTransport.

(Point 3 is easy to get wrong. The response begins with a blank line, so a
`head -c 300 | grep '<!DOCTYPE'` check reports no HTML and appears to
contradict points 1 and 2. It was this document's fourth false negative from an
unvalidated probe; read the actual bytes before believing a one-line test.)

**Practical use.** Firefox 115 ESR is the actual fix and should be the default.
But if Safari must be used — or to read a page whose live version is stuck —
prefixing the URL with `https://archive.today/newest/` will usually produce a
readable copy. `archive.vn` and `archive.today` currently resolve to the same
address (103.70.115.11); `archive.ph` is a separate host, so it is worth trying
if one mirror is down.

Caveats, all observed here:

- It is not reliable. This machine's own history records a `502 Bad Gateway`
  from the service and a `/wip/` URL, which is what an archive still being
  captured looks like.
- It serves a snapshot. The copy may be stale, or may not exist for a given
  URL, in which case it must be requested and waited for.
- It is a third party. Do not authenticate through it, do not send it anything
  private, and do not rely on it where the live page's accuracy matters.

### Why MacPorts was not the answer

MacPorts is installed and working (2.12.6, 167 active ports), but offers no GUI
browser for this platform. No `firefox` port exists, and the only `chromium`
matches are an unrelated game and a tab-widget library. `port diagnose` also
reports that no supported Xcode is installed — MacPorts wants 9.x or 10.x here
— so building a browser from source is not available either.

## Resolution

Firefox 115 ESR is the last branch supporting macOS 10.12–10.14 and is still
receiving security updates. Version 115.41.0esr was published **14 September
2026**, five days before this diagnosis, so the branch is demonstrably alive
rather than merely still downloadable. For scale, the current release branch is
at 156.0 and the mainline ESR is at 140.16.0.

Mozilla has extended the 115 ESR window several times for exactly this
population of unsupported-macOS machines. Treat that as a reprieve, not a
guarantee: the branch will end eventually, and no announcement of the end date
was checked here. `scripts/check-browser-stack.sh` reports the installed
version against Mozilla's current published version on every run, so a branch
that stops moving will become visible over time.

Firefox ships its own NSS root store, so it does not depend on the frozen
system keychain at all.

### Cloudflare challenges — Firefox passes them

Firefox 115 ESR on this host **does** complete Cloudflare challenges. Two
independent pieces of evidence from the desktop profile
(`kyxz68qd.default-esr`), both produced by ordinary browsing rather than by a
test harness:

1. A `cf_clearance` cookie is present for `.claude.ai`. Cloudflare issues that
   cookie only after a challenge has been solved.
2. The visit to `www.reddit.com` at 14:27 was recorded with the URL
   `?solution=...&js_challenge=1&jsc_token=...`, which is the post-solution
   redirect of a JavaScript challenge.

So the browser executes challenge JavaScript and satisfies Cloudflare. Any
future failure needs a more specific explanation than "Firefox 115 is too old
for Cloudflare", because that claim is contradicted here.

### A report that did not survive checking

Early in this work, pages behind Cloudflare's interstitial were reported as
stalling — specifically

    https://apple.stackexchange.com/questions/428728/...

which returns `cf-mitigated: challenge` with `cType: 'precursor_interstitial'`.
That report was **tested in GUI Firefox and does not reproduce. The page
loads.**

It is kept here because the way it nearly became a documented fact is worth
remembering. The report predated the Firefox install, so it described Safari
rather than Firefox; `apple.stackexchange.com` appears zero times in Firefox's
history database, checked with `sqlite3` against a copy including the `-wal`
file. Every attempted reproduction in between was headless, and headless cannot
test challenge completion at all. Three separate signals said "no observation
here", and the draft still called it a known limitation of Firefox.

There is no known site that Firefox 115 ESR fails to load on this machine.

### How to test browser behaviour here, and how not to

Three tools were used during this diagnosis that cannot answer questions about
browsers. Each produced a confident wrong answer first.

1. **`openssl` does not use the system trust store.** The binary here is
   LibreSSL 2.2.7 with its own trust logic. Its `unable to get local issuer
   certificate` errors look like proof of a broken keychain and are not. Use
   `nscurl`, which runs on CFNetwork/SecureTransport like Safari does.
2. **`curl` is challenged by Cloudflare from every machine.** The same URL
   returns an identical 403 from a fully patched host on the same LAN, with a
   modern user agent. Cloudflare scores the TLS fingerprint, not the user agent
   string, so a spoofed UA proves nothing about the browser it names.
3. **Headless Firefox cannot test challenge completion.** `--screenshot` fires
   on the interstitial's load event and exits before the challenge's post-load
   work can run, and Cloudflare scores headless clients as automated anyway. A
   headless run always shows `__cf_bm` present and `cf_clearance` absent. That
   is an artifact of the method, not a finding.

What does work: load the page in the GUI on the console, and read the result
out of the profile afterwards. The `cf_clearance` and `js_challenge` evidence
above came from `~/Library/Application Support/Firefox/Profiles/*.default-esr`
after ordinary browsing. Query it by copying `places.sqlite` and
`places.sqlite-wal` together and using `sqlite3`; a `strings` scan misses
recent writes and will report a visit as never having happened.

A note on that particular page, since it was the source of the original
certificate theory: it is from October 2021, closed as a duplicate, and
describes the Let's Encrypt DST Root CA X3 expiry on macOS 10.11 and earlier.
Its advice — import `ISRG Root X1` by hand — does not apply here. That root is
already present on this machine, the OS is 10.13 rather than 10.11, and the
`nscurl` test above shows the trust path working. Following it is what produced
the leftover files in `~/Downloads`.

Installed:

    /Applications/Firefox.app   Mozilla Firefox 115.41.0esr

SHA-256 verified against Mozilla's published `SHA256SUMS` before install:

    44f4215e815b9cdf3f11bd2543a438e0876df39794c91775295e9279cdc7d9bf

Owned by `andrewrich:staff`, deliberately. `/Applications` is `root:admin 775`
and the account is in `admin`, so an ordinary copy works. Installing with
`sudo` leaves the bundle root-owned and silently breaks Firefox's in-app
updater for ESR point releases — which, on a machine whose security posture
depends entirely on this one application staying current, matters more than it
normally would. The first install here made that mistake and it was corrected;
`scripts/install-firefox-esr.sh` no longer uses `sudo` and verifies ownership
after copying.

### Verification

Headless render tests, all passing:

| Site                  | Result | Output |
|-----------------------|--------|--------|
| claude.ai             | OK     | 148 KB |
| <www.cloudflare.com>    | OK     | 2.9 MB |
| github.com            | OK     | 1.7 MB |
| <www.google.com>        | OK     | 56 KB  |
| <www.reddit.com>        | OK     | 1.5 MB |
| en.wikipedia.org      | OK     | 4.0 MB |

Screenshots of claude.ai and github.com were inspected visually and render
completely: web fonts, gradients, layout, and footer all correct — the claude.ai
login form with its Google and Apple buttons, and the full GitHub landing page
including gradients and footer.

Confirmed in the GUI as well: Firefox was launched from the desktop and loaded
claude.ai with the full login interface, while Safari on the same machine and
the same URL produced no interface at all. Both captures are preserved in
`~/Downloads` on the host (`Claude-firefox.html` with its `_files` directory,
and `Claude-safari.webarchive`) and are the basis for the comparison table
above. Keep them — they are the primary evidence for this diagnosis.

## Operating notes

1. First load after launch can take 60–150 seconds. Cold start on a 2011 Core
   i5 with 4 GB RAM is slow; subsequent loads are ~10 seconds. An early
   `www.reddit.com` timeout was cold-start contention, not a block — it
   succeeded in 10 seconds on retry.
2. 4 GB RAM is the real ceiling. Keep tab counts low.
3. `timeout(1)` does not exist on 10.13. Scripts must use a background-and-poll
   loop instead.
4. Any script that drives Firefox on this host must pass `--no-remote` and a
   throwaway `--profile`. Without both, it attaches to the browser already open
   on the desktop: the script reports spurious failures and the desktop session
   is disturbed. A `www.cloudflare.com` FAIL during this work was exactly that
   collision, not a broken page.
5. Chromium Legacy (blueboxd) was considered and rejected: its last release was
   May 2024 (Chromium 124) and it is no longer updated. Firefox 115 ESR is
   maintained and is the better choice.
6. Safari remains installed and remains broken for modern sites. Use Firefox.
7. Do not leave Safari sitting on a Cloudflare-challenged page. It retries
   roughly every 32 seconds, indefinitely, with nobody at the keyboard. Three
   such tabs added 27 challenge visits to the browser history during the few
   hours this document was being written. Closing the tab stops it.
8. If Safari must be used for a page that will not load, an `archive.today`
   mirror will usually render it — see "Archive mirrors work in Safari".

## Reproducing the diagnosis

Run `scripts/check-browser-stack.sh` from asiago. It re-runs every probe above
and is safe to run repeatedly — it reads state and does not modify the host.
