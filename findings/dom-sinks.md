# DOM sinks (review leads, not confirmed findings)

Static matches in first-party JavaScript. Exploitability depends on whether
attacker-controlled input reaches the sink, which this passive pass cannot
establish. Triage before treating any row as a vulnerability.

| Sink | Occurrences | Example location |
|---|---|---|
| `innerHTML` | 2 | `mirror-raw/localhost:8080/assets/app.bundle.js:9` |
| `document.write` | 1 | `mirror-raw/localhost:8080/assets/app.bundle.js:29` |
| `eval` | 1 | `mirror-raw/localhost:8080/assets/app.bundle.js:30` |
| `postMessage listener` | 1 | `mirror-raw/localhost:8080/assets/app.bundle.js:34` |

**postMessage listener with no `event.origin` comparison anywhere in the
bundle.** Any page that can obtain a handle to this window can send it
messages. Where the handler writes to the DOM, that is a direct injection path.

Total sink occurrences: 5.
