# webbin-sandbox — passive frontend audit pipeline

Spins up a client's public frontend inside a contained sandbox, mirrors and
renders it, and produces a reviewable, re-runnable findings baseline. Re-run
after a fix and diff to prove it landed.

**Passive by construction.** GET only. No authentication, no form submission,
no fuzzing, no brute-forcing. `bin/guard.sh` enforces this in code rather than
in documentation — its `audit_get` helper cannot issue a write request.

## Run it

```bash
npm install
./bin/fixture-up.sh                                    # local fixture on :8080 + :8081
AUDIT_ENV=fixture/fixture.env ./bin/run-audit.sh       # full pipeline, ~9s
./bin/fixture-down.sh
```

Against a real target, edit `audit.env` and run `./bin/run-audit.sh`.

## Before a client run — required

1. **Set `OWNERSHIP`** in `audit.env`. Non-loopback targets are refused without
   it (exit 78). This is not a formality; it is the record of why we were
   allowed to fetch the site.
2. **Set `AUDIT_CONTACT`** to a monitored role address. It goes in the
   User-Agent and lands permanently in the client's access logs. Never a
   personal address.
3. **Declare `EXTRA_HOSTS`** explicitly. There is no `auto` mode — unbounded
   host spanning is how a site mirror becomes a crawl of the open web.
4. **Move this repo to private, or keep captures out of it.** `mirror-raw/`,
   `rendered/`, `har/` and `sourcemaps/` are gitignored precisely because a
   public mirror of a client site can carry live credentials and their original
   source. `mirror-manifest.txt` (hashes) is committed instead of the bytes.

## Pipeline

| Phase | Script | Gate |
|---|---|---|
| 1 Environment | `bin/phase1-env.sh` | every tool prints a version; chromium actually launches |
| 2 Routes | `bin/phase2-routes.sh` | routes.txt non-empty and within budget; 5 sampled URLs return 200 |
| 3 Mirror | `bin/phase3-mirror.sh` | JS+CSS present; **zero faceted URLs on disk**; no 429/503 |
| 4 Rendered crawl | `crawl.js`, `bin/phase4-crawl.sh` | HTML/HAR count matches routes; FAIL rate ≤2%; every request classified |
| 5 Analysis | `bin/phase5-analyze.sh` | 8 findings files present; halts on CRITICAL secrets |
| — Self-test | `bin/verify-fixture.sh` | 17/17 planted defects detected |

A failed gate stops the run. Later phases never build on a broken baseline.

## Why the fixture exists

`fixture/` is a two-origin site with defects planted on purpose and an answer
key in `fixture/expected.tsv`. Without it, "the site is clean" and "the scanner
silently broke" produce identical output.

That is not hypothetical. Four scanners in this repo shipped a **passing gate on
wrong output** during development — an api-surface filter on a HAR field
Playwright does not emit, a reject-regex that leaked faceted URLs, a
colon-splitter that shredded `host:port` paths, and a word boundary that never
matches inside `apiSecret`. Each was caught by the answer key, not by the gate.
Run `bin/verify-fixture.sh` after any scanner change.

## Politeness

`REQ_DELAY_MS` (default 500) is enforced globally in `crawl.js` across *all*
requests, not just navigations — a page load pulls 20+ subresources, and gating
only navigations still bursts them at the origin. wget uses the same value.

That sets a hard ceiling: ~2 requests/second, so roughly **3,600 requests per 30
minutes**. `MAX_ROUTES` and `PHASE_TIMEOUT_SEC` stop a run before it silently
exceeds that. If a real target needs more, raise the budget deliberately —
do not lower the delay.

On 429 or 5xx the pipeline stops and reports. It does not retry harder.

## Secrets protocol

Values are redacted at the point of detection: the raw string never reaches a
file, a log, or the terminal. Truncation scales with length so short values
cannot leak a usable fraction. A CRITICAL hit writes `findings/SECRETS.md` and
halts the phase — but the secret scanner runs **last**, so the halt does not
discard the other seven checks.

`findings/secrets.md` has an INFO tier for values that are public by design
(publishable keys, Sentry DSNs, Firebase web config). These are recorded so
they are recognised and *not* reported as leaks.

If a real credential is found: **rotate first, report second.** Anything served
to a browser must be assumed already harvested.

## Layout

```
audit.env            target, allowlist, politeness, budgets
bin/guard.sh         rules-of-engagement interlocks; GET-only fetch primitive
bin/phase*.sh        one script per phase
bin/scan-*.sh        one scanner per check
crawl.js             Playwright capture: DOM, screenshot, HAR, console, websockets
patterns/secrets.tsv severity-tagged secret patterns
fixture/             local test site + answer key
findings/            per-check output
FINDINGS.md          the report
api-surface.txt      handoff to the backend phase — endpoints listed, never probed
mirror-manifest.txt  sha256 per mirrored file; committed in place of the bytes
```
