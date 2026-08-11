# Third-party inventory

Origins the site loaded during the rendered crawl, by request count.

| Requests | Origin | First-party? | Blocking script |
|---|---|---|---|
| 33 | `http://localhost:8080` | yes | no |
| 1 | `http://127.0.0.1:8081` | yes | **yes** |

External origins outside the declared allowlist: **0**.

Each one executes with full access to the page: DOM, cookies not marked
HttpOnly, and anything typed into a form. For a trading or wallet frontend
this is the single highest-leverage compromise path -- the attacker does not
need our infrastructure, only one of theirs.
