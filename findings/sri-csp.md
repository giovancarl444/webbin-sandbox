# Subresource integrity and CSP

## Cross-origin subresources without integrity

| Tag | URL | Referenced in |
|---|---|---|
| script | `http://127.0.0.1:8081/widget.js` | `rendered/localhost-8080-index-html.html` |

## CSP

**No Content-Security-Policy header.** Nothing constrains which origins may
execute script, so SRI is the only remaining control and it is absent above.

Missing integrity on 1 cross-origin subresource(s).
