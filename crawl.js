/* Phase 4 -- rendered crawl. wget does not execute JavaScript, so anything
   client-rendered is invisible to the mirror. This loads each route as a
   normal anonymous visitor would and records what actually happens.

   Passive by construction: it navigates and observes. It never clicks,
   submits, or synthesises a request. Requests the page makes on its own are
   the site's behaviour and are recorded as observed. */
const { chromium } = require('playwright');
const fs = require('fs');

const routes = fs.readFileSync('routes.txt', 'utf8').split('\n').map(s => s.trim()).filter(Boolean);
const DELAY = +(process.env.REQ_DELAY_MS || 500);
const CONC = +(process.env.CONCURRENCY || 2);
const TIMEOUT = +(process.env.PAGE_TIMEOUT_MS || 60000);
const FULL_PAGE = process.env.FULL_PAGE_SHOTS === '1';
const UA = process.env.AUDIT_UA || 'Webbin-Audit/1.0';

// Global serialised request gate. Applied to every request, not just
// navigations: a page load pulls 20+ subresources, and gating only the
// navigation would still burst them at the origin.
let chain = Promise.resolve();
const gate = () => (chain = chain.then(() => new Promise(r => setTimeout(r, DELAY))));

const slug = u => {
  const p = new URL(u);
  return (p.host + p.pathname).replace(/[^a-zA-Z0-9]+/g, '-').replace(/^-|-$/g, '') || 'index';
};

(async () => {
  for (const d of ['rendered', 'har', '.audit-raw']) fs.mkdirSync(d, { recursive: true });
  const w = f => fs.createWriteStream(f);
  const [log, consoleOut, wsOut, interactive] =
    ['crawl.log', '.audit-raw/console.jsonl', '.audit-raw/websockets.txt', '.audit-raw/interactive.tsv'].map(w);

  const browser = await chromium.launch({ headless: true });
  let next = 0, ok = 0, fail = 0;

  const worker = async () => {
    while (next < routes.length) {
      const url = routes[next++], s = slug(url);
      // HAR is context-scoped, so each route gets its own context. content is
      // omitted: response bodies live in mirror-raw already, and keeping them
      // out of HARs avoids duplicating any secret material into a second file.
      const ctx = await browser.newContext({
        userAgent: UA, ignoreHTTPSErrors: false,
        recordHar: { path: `har/${s}.har`, content: 'omit' },
      });
      try {
        await ctx.route('**/*', async r => { await gate(); await r.continue(); });
        const page = await ctx.newPage();
        page.on('console', m => m.type() === 'error' &&
          consoleOut.write(JSON.stringify({ url, kind: 'console', text: m.text() }) + '\n'));
        page.on('pageerror', e =>
          consoleOut.write(JSON.stringify({ url, kind: 'pageerror', text: String(e.message) }) + '\n'));
        // WebSockets are absent from HAR but central to price-feed frontends.
        page.on('websocket', ws => wsOut.write(`${url}\t${ws.url()}\n`));

        const resp = await page.goto(url, { waitUntil: 'load', timeout: TIMEOUT });
        await page.waitForLoadState('networkidle', { timeout: TIMEOUT }).catch(() => {});
        await page.waitForTimeout(400); // settle for late-firing XHR

        fs.writeFileSync(`rendered/${s}.html`, await page.content());
        await page.screenshot({ path: `rendered/${s}.png`, fullPage: FULL_PAGE });

        // Interactive state a passive load cannot exercise. Reported, not clicked.
        const c = await page.evaluate(() => ({
          forms: document.querySelectorAll('form').length,
          buttons: document.querySelectorAll('button,[role=button]').length,
          inputs: document.querySelectorAll('input,select,textarea').length,
          steps: document.querySelectorAll('[data-step],[data-wizard],.stepper').length,
        }));
        interactive.write(`${url}\t${c.forms}\t${c.buttons}\t${c.inputs}\t${c.steps}\n`);
        log.write(`OK   ${resp ? resp.status() : '---'}  ${url}\n`);
        ok++;
      } catch (e) {
        log.write(`FAIL ---  ${url}  ${String(e.message).split('\n')[0]}\n`);
        fail++;
      } finally {
        await ctx.close().catch(() => {}); // close flushes the HAR
      }
    }
  };

  await Promise.all(Array.from({ length: CONC }, worker));
  await browser.close();
  await Promise.all([log, consoleOut, wsOut, interactive].map(
    st => new Promise(r => st.end(r))));

  const rate = routes.length ? (fail / routes.length) * 100 : 0;
  console.log(`  routes=${routes.length} ok=${ok} fail=${fail} (${rate.toFixed(1)}%)`);
  // A hard zero-FAIL gate blocks on normal conditions (one stale sitemap
  // entry, one slow third party) and creates pressure to fudge the log.
  // 2% with every failure named is the honest threshold.
  if (rate > 2) { console.error('  GATE FAIL: failure rate above 2% -- see crawl.log'); process.exit(3); }
  if (fail) console.log('  NOTE: failures present but within threshold; each is listed in crawl.log');
})().catch(e => { console.error('crawl.js aborted:', e); process.exit(1); });
