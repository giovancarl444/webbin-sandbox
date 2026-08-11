# CRITICAL: credential material in publicly served files

Detected 1 high-confidence credential(s) in files any anonymous
visitor can download. Values below are redacted.

| Pattern | Evidence (path:line) | Redacted |
|---|---|---|
| AWS access key id | `mirror-raw/localhost:8080/assets/config.gen.js:6` | `AKIAIOSF…` |

## Required actions, in order
1. **Rotate the credential now.** It has been publicly served; assume harvested.
2. Audit the provider's access logs for use from unexpected addresses.
3. Remove it from the build output; move it behind a server-side call.
4. Only then re-run this pipeline to confirm.
