# parmesan.local — setup timeline and field notes

Raw record of bringing a free Craigslist 2011 iMac to the point where it could
browse the modern web, and of getting an AI coding agent pointed at it.

Compiled 2026-09-19 from primary sources, not from memory:

- `~/.bash_sessions/*.history` on parmesan (per-session shell history)
- `~/Library/Safari/History.db` on parmesan (timestamped, and by far the
  richest record — browser history preserved the failure loops in a way shell
  history could not)
- `~/.claude/history.jsonl` on asiago
- MacPorts install directory mtimes under
  `/opt/local/var/macports/software/`
- Live verification on both hosts

Times are PDT. Where a claim rests on inference rather than a record, it says
so.

## The hardware

| | |
|---|---|
| Model | iMac12,1 — 21.5-inch, mid 2011 |
| CPU | Intel Core i5-2400S @ 2.5 GHz, 4 cores |
| RAM | 4 GB |
| GPU | AMD Radeon HD 6750M, 512 MB |
| Disk | 466 GB, 19 GB used |
| OS | macOS 10.13.6 High Sierra, build 17G14042 |
| Cost | Free, from Craigslist |

10.13.6 is the last macOS this hardware runs. Its final security patch was in
2020.

---

## Day 1 — Wednesday 2026-09-17

**23:26** First searches from the machine itself: `iMac (21.5-inch, Mid 2011)`,
then straight to the question everyone asks first — whether it can be forced
onto a newer macOS. Three sources consulted, including
`apple.stackexchange.com/questions/435825`, "Can I upgrade a 2011 iMac beyond
High Sierra 10.13.6".

Answer: no. Establishes the constraint the entire project runs into from here.

**23:32** First shell session opens. One command: `date`.

**23:35** `brew.sh`, then immediately `docs.brew.sh/Support-Tiers`.

**23:36** `macports.org`, then `macports.org/install.php`.

Nine minutes from opening Homebrew's site to abandoning it for MacPorts. The
support-tiers page is the pivot: Homebrew does not support High Sierra.
MacPorts still does.

**23:50** `/Library/Developer/CommandLineTools` is created. The Xcode Command
Line Tools land tonight, not on Day 2 — the `xcode-select --install` calls in
the next day's shell history are re-runs against an install that already
succeeded.

---

## Day 2 — Thursday 2026-09-18

**09:11** `softwareupdate --list --all --verbose`, then
`sudo softwareupdate --install --all --restart`. Pull whatever Apple still
offers.

**09:11** `/bin/bash -c "$(curl -fsSL .../Homebrew/install.sh)"` — Homebrew
attempted anyway, despite the previous night's research. It does not survive:
no `/usr/local/Homebrew` or `/opt/homebrew` exists on the machine today.

**09:11** `xcode-select --install`. This one works and matters later: the
Command Line Tools are what make MacPorts able to compile anything at all.

**09:54–10:09** The update-and-reboot cycle repeats across three shell
sessions. `xcode-select -p`, `-v`, `--install` again.

**10:05–10:08** Passwordless sudo research, in Safari on the machine:
`sudoers nopasswd generator`, `askubuntu.com/questions/147241`,
`spinupwp.com/doc/passwordless-sudo/`.

**10:09** The sudo work, and a detail worth noting — **`/etc/sudoers.d` did not
exist on this machine.** It had to be created:

```
sudo mkdir /etc/sudoers.d
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee $USER-user
sudo -k
touch test          # fails, as expected
sudo touch test     # succeeds, no password
sudo rm test
```

Note the verification: revoke the cached credential with `sudo -k`, then prove
the new rule works rather than assume it. This is why passwordless sudo is
available to automation on this host today.

**10:10** First certificate search: `high sierra certificate update` →
`apple.stackexchange.com/questions/422332`, "How do I update my root
certificates on an older version of Mac OS". Safari revisits that page seven
times over 80 seconds — the signature of a page that will not settle.

**10:17–10:26** The certificate theory is acted on. Artifacts still in
`~/Downloads`:

- `cacert.pem` (10:17) — the full Mozilla CA bundle
- `ISRG Root X1.der` (10:26) — the Let's Encrypt root, fetched individually
- `trustroot.sh` (10:21) — splits a PEM bundle and runs
  `security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain`
  on each certificate

**10:25** MacPorts installs `apple-pki-bundle` — the same theory, pursued
through the package manager.

None of it fixed browsing. The reason, established a day later: the OS trust
path was never broken. See `browser-diagnosis.md`.

**12:27** Hostname set. `PARMESAN` across all three of `HostName`,
`LocalHostName` and `ComputerName`, with `dscacheutil -flushcache` after, and
then a loop to read all three back and confirm.

---

## Day 3 — Friday 2026-09-19

### Morning: inventory and networking

**11:49** Safari opens `claude.ai`, redirects to `claude.ai/login`. First
attempt to use the machine for its intended purpose. It does not work.

**~12:00** `system_profiler` captured to `parmesan.txt`, with several attempts
at the redirection (`&>>`, `|& tee -a`, plain `>>`), backgrounding, and
`tail -F` to watch it. On this hardware a full `system_profiler` takes long
enough to be worth watching.

**12:19** `safari-extensions.apple.com` — an attempt at the browser problem
from the extension angle.

**12:30–12:40 — the challenge loop.** This is the clearest single artifact in
the entire record.

Safari is on `apple.stackexchange.com/questions/257813` (passwordless sudo).
The history shows the same URL reloading with a fresh
`__cf_chl_rt_tk=...` token roughly every 32 seconds, alternating with the
bare URL, for ten solid minutes:

```
12:30:50  ...enable-sudo-without-a-password-on-macos?__cf_chl_rt_tk=.BTZzHv_...
12:30:52  ...enable-sudo-without-a-password-on-macos?__cf_chl_rt_tk=JUA_LfsW...
12:31:00  ...enable-sudo-without-a-password-on-macos?__cf_chl_rt_tk=rTaK.KuY...
12:31:32  ...enable-sudo-without-a-password-on-macos?__cf_chl_rt_tk=YRXyPGu_...
          ... continuing every ~32s through 12:40:01
```

That is Cloudflare issuing a challenge, Safari failing it, Cloudflare issuing
another. The user never sees a page. Interleaved at 12:31 is
`discussions.apple.com/verify-human/verify.html` — Apple's own site, same
treatment.

Counted at 16:15 the same day: **139 visits carrying a `__cf_chl_rt_tk`
token**, of which 87 belong to this midday block and 22 are this one
StackExchange question.

This total is not stable. A re-count while finalising this document returned
**159** — twenty more visits, with nobody at the keyboard. A Safari window left
open on a challenged page keeps retrying indefinitely; see the 16:02 entry
below. Treat any figure here as a reading taken at a moment, not a constant.

**12:38:53** `remotedesktop.google.com` appears mid-loop. The first sign of
looking for a way to drive this machine from somewhere else.

**12:37–12:40** Networking out. `ssh-copy-id asiago.local`, then `ssh
asiago.local` — the link this whole session runs over. Then `ssh-keygen`
(parmesan had no key yet), `ssh-copy-id andrewrich@mimolette.local`,
`ssh-copy-id tilsit.local`, and:

```
until ssh tilsit.local hostname; do sleep 5; done; ssh tilsit.local
```

A poll-until-it-answers loop, for a machine that was still booting.

The house is named after cheeses: parmesan, asiago, mimolette, tilsit. As of
this writing tilsit answers at 10.0.15.15; mimolette does not respond.

### Claude Code on parmesan, and why it cannot work

This thread starts at 11:53, before the challenge loop above. It is separated
out because it is a self-contained finding, not because it happened later.

**11:53** `sudo port install claude-code` succeeds. `which claude` confirms
`/opt/local/bin/claude`. `claude auth login` is attempted.

It cannot work, and the reason is absolute:

```
$ /opt/local/bin/claude --version
dyld: cannot load 'claude' (load command 0x80000034 is unknown)
Abort trap: 6
```

The port installs a shell wrapper around a Mach-O binary whose load commands
this OS predates. Verified directly:

```
$ otool -l /opt/local/share/claude-code/claude | grep -A4 LC_BUILD_VERSION
       cmd LC_BUILD_VERSION
  platform macos
       sdk 26.5
     minos 13.0
```

The binary requires **macOS 13.0** and was built against **SDK 26.5**. High
Sierra's `dyld` does not recognise `LC_BUILD_VERSION` (load command
`0x80000034`) and aborts before executing a single instruction. No
configuration, flag or patch reaches this; the loader rejects the file.

**This is the decision point for everything that follows.** The agent cannot
run on parmesan. It has to run on asiago and reach parmesan over SSH — which
is exactly the arrangement in use now.

### Afternoon: the browser hunt, and 167 ports

MacPorts base was installed 2026-08-25. The bulk of the port installs happen in
a single block today.

**13:22:05–13:41:33** — **165 ports installed in 19 minutes 28 seconds**, on a
four-core 2011 CPU. (`/opt/local/var/macports/software/` holds 167 directories;
the other two are `apple-pki-bundle` from Day 2 and `claude-code` from 11:53
today.) An install directory's mtime records when the port was written to disk,
not how long it took to compile — MacPorts serves many ports from prebuilt
archives, so this block is not 165 compilations. Selected timestamps:

| Time | Port | Note |
|------|------|------|
| 13:22 | zlib, brotli, curl-ca-bundle | foundations |
| 13:24 | harfbuzz | text shaping |
| 13:26 | **w3m** | a terminal browser — no JavaScript |
| 13:29 | clang-17 | a whole compiler, as a dependency |
| 13:30 | python313 | and Python 3.14 alongside it |
| 13:41 | **qt4-mac** | the last port built |

The chain was aimed at **Arora**, a Qt4 WebKit browser, and later
**litebrowser**:

```
sudo port install arora
sudo port run arora
open arora -a macports
open /Applications/MacPorts/Arora.app/
tree /Applications/MacPorts/
```

That last sequence — trying four different ways to launch the same
application — is what looking for something that was never built looks like.

**Neither browser is installed now.** Verified:

```
$ port installed arora litebrowser
None of the specified ports are installed.
```

Both ports exist in the tree (`arora @0.11.0`, `litebrowser @0.0.0-20211116`),
and the Arora source tarball was downloaded — `distfiles/arora/arora-0.11.0.tar.gz`
is still there. `/Applications/MacPorts/` today contains Qt4, Python 3.13 and
Python 3.14 — the dependencies — and no browser. The searching continued:

```
port list | grep browser
port search web browser | less
```

**Arora did run, though, and it left a confession.**
`~/Library/Preferences/org.arora-browser.Arora.plist`, written at 13:54,
contains its saved state:

```
"toolbarsearch.recentSearches" = ( "make a qr code from url" )
"sessions.lastSession" = ... "qrc:/startpage.html" ... "Welcome to Arora!" ...
```

Arora was launched, and the search string `make a qr code from url` was typed
into its toolbar during the QR-code hunt. But the search never went anywhere:
**Arora could not load Google at all** (confirmed by the operator). Its last
session is still sitting on `qrc:/startpage.html`, the built-in welcome page
served from inside the application bundle — the only page it ever displayed.

A saved search in a browser's preferences records what was typed, not what
loaded. Arora reached nothing. The QR code was eventually obtained through
Safari.

Net result of the afternoon: **165 ports installed, one terminal browser with no
JavaScript, one Qt4 browser that could not load Google, and Qt4 itself left
standing as the tombstone.**

### 13:57–14:05 — the QR code login

The problem, stated plainly: Claude Code on asiago needs an OAuth login. OAuth
means opening a URL in a browser. The browser on the machine physically in
front of the user — parmesan — cannot render `claude.ai`.

The record, from Safari's history — and, before that, from Arora's:

**~13:54** Arora is launched and `make a qr code from url` is typed into its
search bar. **Arora cannot load Google**, so nothing comes back. It never
leaves its own welcome page. (Recovered from
`org.arora-browser.Arora.plist`; Arora keeps no timestamped history, so this is
dated by the plist's mtime.)

**13:57:12** The attempt moves to Safari, which at least reaches the search:
`google.com/search?q=qr+code+from+url`

**13:58:18** The OAuth URL is pasted into Safari on parmesan:

```
claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a-...&response_type=code&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Fo...
```

It redirects to `claude.ai/oauth/authorize?...` and does not render.

**13:58:25** Tried a second time. Same result.

**13:58:57–13:59:36** Hunting for a QR generator that will itself load on a
2020 browser:

- `qr-codes.com/decoder` — wrong tool, that decodes
- `app.qr-codes.com/register` — wants an account
- `ithelp.brown.edu/kb/articles/how-to-share-a-webpage-as-a-qr-code` — a
  university IT help article, consulted in earnest
- `help.brown.edu/servicedesk/...`

**13:59:45** `me-qr.com/qr-code-generator/link` — this one renders.

**13:59:54** `me-qr.com/qr-code-generator/qr` — the code is generated.

**14:05:07–14:05:14** Back through the generator twice more. A fresh OAuth URL,
or a second attempt at the same one.

The full path the credential actually travelled:

1. OAuth URL produced by Claude Code on **asiago**, displayed over SSH
2. Pasted into Safari on **parmesan**, which cannot render claude.ai. Arora was
   tried first and could not load anything at all
3. Pasted instead into `me-qr.com` — reached in Safari after several generators
   that would not load or demanded an account — to render a QR code **as an
   image**
4. QR code photographed from the parmesan screen with a **phone**
5. The phone — a modern browser — opens claude.ai and completes the OAuth flow
6. Auth code copied on the phone
7. **Continuity clipboard** carries it from the phone to asiago
8. Read back over the SSH session and pasted into the waiting prompt

Eight hops, two machines, a phone, a camera and a QR code, to move one string
that both endpoints could already see. The image was the transport because it
was the only format every link in the chain could handle.

**14:10:03** The Claude Code session on asiago receives its first message:

> hello. you are, at great effort and hair pulling, running in:

The message was truncated. The second attempt, at 14:11:20, explains the
environment.

### 14:12 onward — the diagnosis

See `browser-diagnosis.md` for the technical account. In summary: the
certificate theory was tested and rejected; Safari 13.1.2 turned out to be
receiving pages correctly and failing to execute their JavaScript; Firefox 115
ESR was installed at 14:24 and works.

Three tools gave confident wrong answers along the way — `openssl` (does not
use the system trust store), `curl` (challenged by Cloudflare from every
machine, including fully patched ones) and headless Firefox (exits before a
challenge can complete). Each is documented in `browser-diagnosis.md` so the
next person does not repeat them.

**15:55** The session is moved into a server-side `tmux` after an interruption,
so that 2011-era instability cannot kill it again.

**16:02–16:09** A coda worth recording. While Firefox was confirming that
`apple.stackexchange.com/questions/428728` loads fine, **Safari was looping on
that same URL in the background** — same 32-second `__cf_chl_rt_tk` cadence as
the 12:30 loop, over 40 visits. Both browsers, same machine, same URL, same
moment: one renders the page, the other cannot get past the door.

---

## Tally

What the machine has to show for three days:

| Attempt | Outcome |
|---|---|
| Upgrade past High Sierra | Impossible on this hardware |
| Homebrew | Not supported on 10.13; no trace left |
| MacPorts | Works. 165 ports installed in under 20 minutes |
| Xcode CLT | Installed; makes the compiling possible |
| Passwordless sudo | Works. `/etc/sudoers.d` had to be created first |
| Root certificate imports | Did nothing. The trust path was never broken |
| `apple-pki-bundle` | Same theory, same non-result |
| Claude Code on parmesan | Installs, cannot load. Requires macOS 13.0 |
| Arora | Ran. Could not load Google. Not installed now |
| litebrowser | Never installed |
| w3m | Installed. No JavaScript, so no help |
| Firefox 115 ESR | **Works.** The answer |
| Safari 13.1.2 | Still broken. Still the default browser |

Three days, 165 installed ports, one QR code, and the fix was a 130 MB download
that took four minutes.

## Loose ends

- `mimolette.local` did not respond during this work. Status unknown.
- Arora ran at ~13:54 but `port installed arora` reports it is not installed,
  and no bundle or binary is on disk. Only the source tarball and the
  preferences file remain. How it ran is unresolved — most likely built and
  launched from the build directory, which MacPorts later cleaned.
- `~/Downloads` still holds `cacert.pem`, `ISRG Root X1.der` and
  `trustroot.sh` from the certificate theory. Harmless, and left in place as
  evidence. Do not build on them.
- The Safari retry loop is closed. The `__cf_chl_rt_tk` count climbed from 139
  to 159 to 166 during the writing of this document, entirely unattended. At
  16:24 the three tabs stuck on `Just a moment...` were closed; the count then
  held at 166 across a 90-second sample, against a prior cadence of roughly one
  retry every 32 seconds. 166 is therefore a final figure, not a reading.
- Safari remains the system default browser and remains unable to open most
  sites. Anything automated on this host should invoke Firefox explicitly.
