# System import — bringing a client's stack into the sandbox

The audit engine measures a client's production site passively, from outside.
The import engine reproduces that system **inside the sandbox**, where we can
work on it without touching anything the client depends on.

The connection between the two is the point: **parity between the sandbox copy
and production is the confidence level on every claim we make.**

```
bin/import-system.sh <name> [git-url] [port]   # acquire → detect → provision → build → serve
bin/import-routes.sh <name>                    # routes + API handlers from SOURCE
bin/audit-import.sh  <name>                    # run the full audit against the copy
bin/import-ledger.sh <name>                    # what is faithful, what is not
bin/import-down.sh   <name>                    # tear down
```

## Measured on two real systems

| | `lumora-dental` | `ai-site-clomer-v2` |
|---|---|---|
| Shape | static site, 86 MB, 414 files | Next.js 16 / React 19, 109 files |
| Detected | `static` | `nextjs`, npm, port 3000, `engines.node >=24` |
| Install | n/a | 20 s |
| Build | n/a | 5 s |
| **Time to serving** | **1 s** | **26 s** |
| Routes from source | 18 | 2 |
| Full audit | 2 m 12 s | ~25 s |
| Transferability caveats | 2 | 3 |

Acquire measured 0 s on both because the trees were already cloned; clone time
for the 86 MB repo is not included in the figures above.

## Why routes come from source, not the sitemap

A sitemap lists what a site *advertises*. The source tree lists what it
*serves* — unlinked pages, staging routes, and backend handlers that no passive
crawl will ever reveal. `import-routes.sh` reads Next.js App Router
`page.tsx`/`route.ts` (deriving HTTP methods from the exported handler names,
not from guessing), Pages Router, and static `.html` trees. Dynamic segments
(`[id]`) are separated out rather than emitted as URLs that would 404 and
pollute the error findings.

Source-derived API handlers merge into `api-surface.txt`, which is the handoff
to step 3. Passive observation only catches endpoints some page happened to
call; the source lists every handler that exists.

## The fidelity ledger

Every import writes `imports/_meta/<name>-ledger.md` grading each dimension:

| Dimension | Why it matters |
|---|---|
| Source revision | Pinned SHA — the finding is re-checkable months later |
| Runtime | Built on a different runtime than production? Bundle findings do not transfer |
| Configuration | Every placeholder substituted is behaviour left unexercised |
| Data layer | Services declared but unprovisioned means no backend claim is valid |
| Build | A failed build invalidates every frontend finding |
| Route coverage | Findings only cover routes actually crawled |
| Origin | Loopback copy — TLS/CDN/edge headers belong to the client's edge, never to us |
| External egress | If our proxy blocks a CDN the page needs, console errors are ours, not theirs |

That last row was not designed in advance. It came out of the first real run:
auditing `lumora-dental` produced 26 JavaScript console errors, and they turned
out to be `net::ERR_CONNECTION_RESET` reaching `ajax.googleapis.com` — **this
sandbox's egress proxy**, not a defect in the site. `WebFont is not defined`
was downstream of the same cause. Reporting those to a client as bugs would
have been wrong, confidently and in writing. The ledger now catches it.

That is the whole thesis: a finding from a sandbox copy is a claim about
production only on the dimensions where the copy matches production. Anything
else gets labelled, not asserted.

## Real findings from the first run

`lumora-dental`, all dimensions transferable except egress:

- `ajax.googleapis.com` serves a **render-blocking script with no integrity
  attribute** — the highest-privilege position on the page, from an origin we
  do not control.
- 50 cross-origin subresources without SRI, across 2 external origins.
- 1 `postMessage` listener with no origin check.

`ai-site-clomer-v2` came back clean on secrets, sourcemaps and SRI, which is
what a freshly built Next.js template should look like. The 23 DOM-sink matches
are minified React internals and are labelled as review leads, not findings.

## What is proven, and what is not

**Proven:** static and Next.js imports, source-derived routing, full audit
against an imported copy, fidelity ledger, teardown. The fixture regression
still passes 17/17 after all of it.

**Not yet:** Python, PHP, Ruby and Go have detection but no start strategy —
they report `not implemented` rather than guessing, because a wrong start
command produces a running process that is not the client's system. Service
provisioning (Postgres/Redis via compose) is written but has not met a repo
that declares one. Multi-repo systems (separate frontend/backend) import one at
a time; nothing yet correlates them.

## Conclusions from the first run

1. **The fixture only tested presence, never absence.** Three separate phases
   died on real systems because the fixture always had a WebSocket, always had
   query parameters, always had an API call. `grep`/`rg` exit 1 on no matches,
   and under `pipefail` that killed the phase on the most common real-world
   outcome. The fixture needs negative cases: a site with no third parties, no
   query strings, no dynamic endpoints.
2. **Import is faster than expected and is not the bottleneck.** 26 s for a
   full Next.js install+build. The audit is the slow half (2 m 12 s for 18
   routes), and it is dominated by the politeness delay — which is unnecessary
   against our own copy. `audit-import.sh` already drops it to 10 ms; there is
   more headroom.
3. **Sandbox network isolation is a systematic accuracy risk.** It will affect
   every client site that uses a CDN, analytics, or hosted fonts — which is
   nearly all of them. The ledger flags it; the better fix is an allowlist for
   third-party origins the imported system legitimately needs.

## Open questions

- Do we want production parity checks (sandbox route set vs. live sitemap,
  sandbox bundle hashes vs. live `mirror-manifest.txt`)? The engine already
  produces both halves; nothing joins them yet. This would turn "we imported it"
  into "we imported it and here is the proof it matches."
- For multi-repo clients, what defines "the complete system" — do we need
  service topology from the client, or infer it from compose files?
- Which stack should get a start strategy next? That should follow the waitlist,
  not my guess.
