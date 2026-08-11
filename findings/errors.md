# Console and network errors (bugs, not security findings)

## JavaScript errors

| Kind | Route | Message |
|---|---|---|
| console | `http://localhost:8080/about.html` | Failed to load resource: the server responded with a status of 404 (File not found) |
| console | `http://localhost:8080/about.html` | WebSocket connection to 'ws://127.0.0.1:8081/feed' failed: Error during WebSocket handshake: Unexpected response code: 404 |
| console | `http://localhost:8080/about.html` | fixture-intentional-error: console channel |
| console | `http://localhost:8080/blog/why-custody-matters.html` | Failed to load resource: the server responded with a status of 404 (File not found) |
| console | `http://localhost:8080/blog/why-custody-matters.html` | WebSocket connection to 'ws://127.0.0.1:8081/feed' failed: Error during WebSocket handshake: Unexpected response code: 404 |
| console | `http://localhost:8080/blog/why-custody-matters.html` | fixture-intentional-error: console channel |
| console | `http://localhost:8080/contact.html` | Failed to load resource: the server responded with a status of 404 (File not found) |
| console | `http://localhost:8080/contact.html` | WebSocket connection to 'ws://127.0.0.1:8081/feed' failed: Error during WebSocket handshake: Unexpected response code: 404 |
| console | `http://localhost:8080/contact.html` | fixture-intentional-error: console channel |
| console | `http://localhost:8080/index.html` | Failed to load resource: the server responded with a status of 404 (File not found) |
| console | `http://localhost:8080/index.html` | WebSocket connection to 'ws://127.0.0.1:8081/feed' failed: Error during WebSocket handshake: Unexpected response code: 404 |
| console | `http://localhost:8080/index.html` | fixture-intentional-error: console channel |
| console | `http://localhost:8080/markets.html` | Failed to load resource: the server responded with a status of 404 (File not found) |
| console | `http://localhost:8080/markets.html` | WebSocket connection to 'ws://127.0.0.1:8081/feed' failed: Error during WebSocket handshake: Unexpected response code: 404 |
| console | `http://localhost:8080/markets.html` | fixture-intentional-error: console channel |
| console | `http://localhost:8080/products.html` | Failed to load resource: the server responded with a status of 404 (File not found) |
| console | `http://localhost:8080/products.html` | WebSocket connection to 'ws://127.0.0.1:8081/feed' failed: Error during WebSocket handshake: Unexpected response code: 404 |
| console | `http://localhost:8080/products.html` | fixture-intentional-error: console channel |
| pageerror | `http://localhost:8080/about.html` | fixture-intentional-error: uncaught channel |
| pageerror | `http://localhost:8080/blog/why-custody-matters.html` | fixture-intentional-error: uncaught channel |
| pageerror | `http://localhost:8080/contact.html` | fixture-intentional-error: uncaught channel |
| pageerror | `http://localhost:8080/index.html` | fixture-intentional-error: uncaught channel |
| pageerror | `http://localhost:8080/markets.html` | fixture-intentional-error: uncaught channel |
| pageerror | `http://localhost:8080/products.html` | fixture-intentional-error: uncaught channel |

## Failed requests (4xx / 5xx)

| Status | Method | URL |
|---|---|---|
| 404 | GET | `http://localhost:8080/api/missing-endpoint.json` |

JavaScript errors: 24. Failed requests: 1.

These are correctness and reliability defects. They are listed here so they
are not confused with the security findings, and so they are not lost.
