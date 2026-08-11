# Frontend audit — findings

**Target:** `http://localhost:8080` (local fixture, `fixture/fixture.env`)
**Run:** 6 routes, 12 mirrored files, 6 HARs, 9s wall clock
**Scope:** passive frontend only. No authentication, no writes, no fuzzing. Backend endpoints are listed in `api-surface.txt` for a later phase and were not probed.

> This is the **engine's reference baseline**, not a client report. The target is a
> fixture with defects planted on purpose, so every finding below is one we put
> there — that is what makes it a usable regression test. A client run produces
> this same document against `audit.env`.

Findings are ordered by severity. Security issues, bugs, and hygiene are kept
separate on purpose: inflating a broken image into a vulnerability devalues the
whole report.

---

## Security findings

### 1. AWS access key id served in a public JavaScript bundle — CRITICAL

**Severity justification.** Critical rather than High because the credential is
a long-lived identity, not a scoped browser token, and it is served to every
anonymous visitor with no authentication. There is no exploitation step to
speculate about: retrieval *is* the compromise, and it has already happened for
anyone who fetched the page.

| | |
|---|---|
| **Evidence** | `mirror-raw/localhost:8080/assets/config.gen.js:6` — redacted `AKIAIOSF…` in `findings/secrets.md` and `findings/SECRETS.md` |
| **Impact** | Whatever the IAM principal can reach: object storage, queues, and anything reachable by privilege escalation from it. Server logs will show legitimate-looking API calls, because the calls *are* legitimate — they carry our key. |
| **Fix** | Rotate first, before any code change — the key is public and must be assumed harvested. Then remove it from the build output entirely and move the call it authorises behind a server-side endpoint. A frontend cannot hold a secret; there is no "obfuscate it better" option. |
| **Verify** | `./bin/scan-secrets.sh` exits 0 and `findings/secrets.md` reports `CRITICAL=0` |

### 2. Three further credentials in the same bundle — HIGH

**Severity justification.** High, not Critical: a Stripe *test* key touches no
real money, and the JWT will expire. But all three are live-shaped credentials
in public code, and the pattern — a config object shipped wholesale to the
browser — is the actual defect. Where one key ships, others follow.

| | |
|---|---|
| **Evidence** | `mirror-raw/localhost:8080/assets/config.gen.js:5,7,8` — Stripe test key, CoinGecko market-data key, JWT (all redacted in `findings/secrets.md`) |
| **Impact** | The CoinGecko key is billable: an attacker can exhaust our quota and take the price feed down, which for a trading frontend is a visible outage. The JWT grants whatever its claims carry until expiry. The Stripe test key exposes test-mode data and confirms the deployment pattern for the live key. |
| **Fix** | Split the config: publishable values stay, secret-bearing values move server-side. Add a CI check that fails the build when a secret pattern appears in build output — the durable fix is the gate, not this one removal. |
| **Verify** | `./bin/scan-secrets.sh` reports `HIGH=0` |

### 3. Sourcemap publicly reachable — HIGH

**Severity justification.** High rather than Medium because it is a complete
loss of source confidentiality, not a hint. It also compounds every other
finding: it hands an attacker the readable version of the code they would
otherwise reverse-engineer.

| | |
|---|---|
| **Evidence** | `mirror-raw/localhost:8080/assets/app.bundle.js:45` → `http://localhost:8080/assets/app.bundle.js.map` returns **200** with 2 original sources (`findings/sourcemaps.md`) |
| **Impact** | Reconstructs original source including internal module names, comments, and dead code paths. In this fixture the map exposes `internal/pricing-engine.ts` and a `SPREAD_BPS` constant — commercially sensitive on its own, and a map of where to look for more. |
| **Fix** | Stop publishing maps to the production origin: `productionSourceMap: false`, or upload them to the error tracker and keep them off the web root. If the tracker needs them, restrict by auth rather than obscurity. |
| **Verify** | `./bin/scan-sourcemaps.sh` reports `exposed=0` |

### 4. Cross-origin script with no integrity and no CSP — HIGH

**Severity justification.** High on its own merits, and the two controls fail
together: with no CSP, SRI is the only thing standing between a compromised
vendor and arbitrary execution, and SRI is absent. For a stock or crypto
frontend this is the live attack path — a compromised third-party script is how
wallet drainers reach users, not a theoretical concern.

| | |
|---|---|
| **Evidence** | `rendered/localhost-8080-index-html.html` loads `http://127.0.0.1:8081/widget.js` with no `integrity` attribute (`findings/sri-csp.md`); no `Content-Security-Policy` header on any route (`findings/headers.md`). The tag is render-blocking, so it executes before content paints — the highest-privilege position on the page. |
| **Impact** | Anyone who compromises that vendor executes in our users' sessions: read the DOM, read non-`HttpOnly` cookies, and modify anything shown or typed — including a displayed wallet or payment address. We would not see it in our own logs. |
| **Fix** | Add `integrity` + `crossorigin` to every cross-origin `<script>`/`<link>`, and ship a `Content-Security-Policy` with an explicit `script-src` allowlist. Where a vendor ships mutable code and SRI is impossible, that is a vendor decision to escalate, not a gap to accept silently. |
| **Verify** | `./bin/scan-sri-csp.sh` reports `0` cross-origin subresources without SRI and a CSP with no `unsafe-inline` |

### 5. jQuery 1.8.3 with five known CVEs — MEDIUM

**Severity justification.** Medium, not High: every CVE here is XSS requiring
attacker-controlled input to reach a specific jQuery method, which this passive
pass cannot prove happens. The version is unambiguous; the reachability is not.
Rating it High would be guessing.

| | |
|---|---|
| **Evidence** | `mirror-raw/localhost:8080/assets/jquery-1.8.3.min.js` — CVE-2012-6708, CVE-2015-9251, CVE-2019-11358, CVE-2020-7656, CVE-2020-11023 (`findings/dependencies.md`) |
| **Impact** | If any of `.html()`, `.append()`, or selector construction receives untrusted input, these give script execution in our origin. Combined with finding 4, an attacker has both a delivery route and a sink. |
| **Fix** | Upgrade to 3.7.x, or drop jQuery — the 1.x API surface in use here is a few lines of native DOM code. |
| **Verify** | `./bin/scan-deps.sh` reports 0 findings |

### 6. All six security headers missing — MEDIUM

**Severity justification.** Medium as a group. Individually most are
defence-in-depth, but the absence of `frame-ancestors`/`X-Frame-Options` is
directly exploitable via clickjacking, which raises the set above Low.

| | |
|---|---|
| **Evidence** | `findings/headers.md` — `Content-Security-Policy`, `Strict-Transport-Security`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, `X-Frame-Options` all absent on root and on `/blog/why-custody-matters.html` |
| **Impact** | No framing protection means any in-page action can be clickjacked — for a trading UI, a confirm button is enough. No `nosniff` lets a mistyped content type become script. No `Referrer-Policy` leaks full URLs, including any path-embedded identifiers, to every third party in finding 4. |
| **Fix** | Set them at the edge (CDN/reverse proxy) so they apply to every response including static assets, not per-template. Start `Content-Security-Policy-Report-Only`, then enforce. |
| **Verify** | `./bin/scan-headers.sh` shows no `**MISSING**` rows |

### 7. `postMessage` listener with no origin check — MEDIUM

**Severity justification.** Medium and deliberately not higher: the listener and
the sink are both confirmed present, but this passive pass cannot prove an
attacker can obtain a window handle. It is a real defect with an unproven
reachability, and is reported as such.

| | |
|---|---|
| **Evidence** | `mirror-raw/localhost:8080/assets/app.bundle.js:34` — `addEventListener("message", …)` writing to `.innerHTML`, with no `event.origin` comparison anywhere in the bundle (`findings/dom-sinks.md`) |
| **Impact** | Any frame or opener that can reach this window can inject markup into the page. The handler writes attacker-supplied data straight to `innerHTML`, so this is a direct DOM-XSS path if reachable. |
| **Fix** | Compare `event.origin` against an explicit allowlist as the handler's first statement, and replace `innerHTML` with `textContent` where markup is not required. |
| **Verify** | `./bin/scan-sinks.sh` reports `unchecked-postMessage=0` |

### Not a finding — publishable key

`pk_live_…` at `config.gen.js:4` is Stripe's **publishable** key. It is designed
to ship in client code. It is recorded as INFO in `findings/secrets.md` and is
deliberately not reported as a leak. Filing it as one would burn client trust
and bury findings 1–7.

---

## Bugs (not security)

| Severity | Issue | Evidence | Fix |
|---|---|---|---|
| Medium | 24 JavaScript console errors across all 6 routes — an uncaught `Error` throws on every page load | `findings/errors.md` | Fix the throwing path in `app.bundle.js`; an always-throwing page breaks error monitoring by drowning real signals |
| Low | `GET /api/missing-endpoint.json` returns 404 on every route | `findings/errors.md`, `api-surface.txt` | Remove the dead call or restore the endpoint |
| Low | WebSocket `ws://127.0.0.1:8081/feed` fails its handshake on every page | `findings/errors.md` | Point the price feed at a real endpoint, or drop the connection attempt |

## Hygiene and observations

- **Served over plaintext HTTP.** Fixture-only, but worth stating: HSTS cannot apply and every finding above is also passively observable on the wire. Any real target must be HTTPS before these results mean anything.
- **Absolute mirror size 68 KB / 12 files** — well inside budget; a client site will not be.
- **`robots.txt` discloses `/admin/` and `/internal/`.** Not a vulnerability — robots is a public file and this is normal — but it is free reconnaissance, and both paths should be confirmed to require authentication.

## Interactive state not exercised

A passive load cannot reach behaviour behind a click. These routes carry
interactive state and are **listed, not driven** — scripting them needs explicit
sign-off:

| Route | Forms | Buttons | Multi-step |
|---|---|---|---|
| `/products.html` | 0 | 1 | 1 (`data-step` configurator) |
| `/contact.html` | 1 | 1 | 0 |

The `/contact.html` form POSTs to `/api/subscribe`. It was inventoried and never
submitted.

## Handoff to the backend phase

`api-surface.txt` — 3 endpoints, none probed:

```
GET http://localhost:8080/api/missing-endpoint.json
GET http://localhost:8080/api/quotes.json
WS  ws://127.0.0.1:8081/feed
```

## Re-running

```bash
./bin/fixture-up.sh && AUDIT_ENV=fixture/fixture.env ./bin/run-audit.sh
```

Every fix above states its own verify command. `mirror-manifest.txt` gives a
hash-level diff between runs, so a re-run shows exactly which assets changed.
