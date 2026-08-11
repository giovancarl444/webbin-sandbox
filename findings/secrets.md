# Secrets scan

Values are redacted at the point of detection. To confirm a hit, open the
cited path:line in the local (gitignored) mirror -- never paste the value.

| Severity | Pattern | Evidence (path:line) | Redacted |
|---|---|---|---|
| CRITICAL | AWS access key id | `mirror-raw/localhost:8080/assets/config.gen.js:6` | `AKIAIOSF…` |
| HIGH | CoinGecko API key | `mirror-raw/localhost:8080/assets/config.gen.js:7` | `CG-FIXTURE…0000` |
| HIGH | JSON Web Token | `mirror-raw/localhost:8080/assets/config.gen.js:8` | `eyJhbGciOi…0000` |
| HIGH | Stripe secret key (test) | `mirror-raw/localhost:8080/assets/config.gen.js:5` | `sk_test_FI…0000` |
| MEDIUM | Generic assigned secret | `mirror-raw/localhost:8080/assets/config.gen.js:10` | `Secret: "f…890"` |
| MEDIUM | Generic assigned secret | `mirror-raw/localhost:8080/assets/config.gen.js:7` | `ApiKey: "C…000"` |
| MEDIUM | Generic assigned secret | `mirror-raw/localhost:8080/assets/config.gen.js:8` | `Token: "ey…000"` |
| INFO | Stripe publishable key (public by design) | `mirror-raw/localhost:8080/assets/config.gen.js:4` | `pk_live_FI…0000` |

Totals: CRITICAL=1 HIGH=3 MEDIUM=3 INFO=1

## Triage notes

- INFO rows are **not** findings. Publishable keys, Sentry DSNs and Firebase
  web config are designed to ship in client code. Reporting them as leaks
  buries the findings that matter.
- MEDIUM is a generic assignment pattern with a deliberately high
  false-positive rate; each row needs a human look.
- A CRITICAL hit means rotate first, then report. Anything shipped to a
  browser must be assumed already harvested.
