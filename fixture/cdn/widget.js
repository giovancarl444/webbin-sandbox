/* Third-party widget served from a separate origin (127.0.0.1:8081).
   Loaded with no integrity attribute and no CSP restricting it -- the exact
   shape of the frontend supply-chain compromise that drains crypto wallets.
   TP-01 and SRI-01 exist to prove we detect it. */
(function () {
  window.__meridianWidget = { version: "2.4.1", loaded: true };
})();
