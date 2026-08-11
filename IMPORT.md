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

## Production parity

`bin/parity-check.sh <name> <production-url>` mirrors the **same source-derived
routes** against both the sandbox copy and the live origin, then joins the two
asset manifests by path and by content hash.

Two metrics, because one is misleading:

- **Path parity** — same path, same bytes. Meaningful for static sites.
- **Content parity** — what fraction of production's assets exist byte-identical
  in the sandbox, *ignoring filenames*. Hashed-chunk builds (Next.js, Vite)
  rename every asset per build, so path parity alone reports total mismatch even
  when the shipped bytes are identical.

Verified in both directions on two origins built from identical source:

| | Identical source | After introducing drift |
|---|---|---|
| Same path, identical bytes | 11 | 9 |
| Same path, different bytes | 0 | **1** (the modified bundle, named) |
| Missing from sandbox | 0 | **1** (the deleted page, named) |
| **Content parity** | **100%** | **81%** |

A parity checker that always reports a match is worthless, so the drift case is
part of the test, not an afterthought.

The report ends with what the result licenses us to claim. At ≥95% content
parity with nothing missing, bundle-level findings — secrets, sourcemaps,
vulnerable dependencies, DOM sinks — transfer to production, because the bytes
analysed are the bytes production serves. Below that, they are sandbox-only
until parity improves. Header, TLS and CDN findings never come from this
comparison at all; they belong to the client's edge.

One bug this surfaced: wget's `-D` is port-blind, so a loopback asset host fell
inside one side's scope and outside the other's, inflating the difference count.
Snapshots are now restricted to the target origin before comparison. Inconsistent
scoping silently corrupts the exact number we would put in front of a client.

No live deployment of the example repos was reachable from this sandbox, so
parity was proven against two local origins rather than a real production host.
The mechanism is origin-agnostic; a client run needs only the URL and an
`OWNERSHIP` attestation.

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

1. **The fixture only tested presence, never absence.** ~~The fixture needs
   negative cases.~~ **Done** — `fixture/bare` now covers the empty result, and
   `bin/verify-engine.sh` runs both fixtures as one regression. Building it
   immediately exposed two more bugs of the same family: `<sitemapindex>` was
   matched inside an XML *comment*, so a flat sitemap was expanded as an index;
   and phase 3 hard-failed a site with no JavaScript, which is a legitimate
   brochure site rather than a broken mirror. Five bugs total in this class.
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
