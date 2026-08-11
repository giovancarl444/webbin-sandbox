/* Fixture application bundle. Planted defects are intentional. */
(function () {
  "use strict";

  // SINK-01: unsanitised innerHTML assignment from a network-controlled value.
  function renderTicker(rows) {
    var el = document.getElementById("ticker");
    if (!el) return;
    el.innerHTML = rows.map(function (r) {
      return "<span class='row'>" + r.symbol + " " + r.last + "</span>";
    }).join("");
  }

  // API-01: XHR endpoint the backend handoff needs to know about.
  fetch("/api/quotes.json")
    .then(function (r) { return r.json(); })
    .then(function (d) { renderTicker(d.quotes || []); })
    .catch(function (e) { console.error("quote load failed", e); });

  // ERR-02: request to a route that does not exist -> 404 in the HAR.
  fetch("/api/missing-endpoint.json").catch(function () {});

  // API-02: price-feed websocket. Handshake fails against the static fixture
  // server by design; the URL is still captured at creation time.
  try { new WebSocket("ws://127.0.0.1:8081/feed"); } catch (e) {}

  // Another sink, in a code path that never runs -- exercises static detection.
  window.__debugWrite = function (html) {
    document.write(html);
    return eval("1 + 1");
  };

  // Message listener with no origin check.
  window.addEventListener("message", function (ev) {
    var box = document.getElementById("ticker");
    if (box) box.innerHTML = ev.data;
  });

  // ERR-01: uncaught error, deferred so it does not abort this file.
  setTimeout(function () {
    console.error("fixture-intentional-error: console channel");
    throw new Error("fixture-intentional-error: uncaught channel");
  }, 50);
})();
//# sourceMappingURL=app.bundle.js.map
