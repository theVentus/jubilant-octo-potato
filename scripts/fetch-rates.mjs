// Fetches USD-based rates (no API key) and writes rates.json in the app's format:
// { base: "USD", updated: ISO string, source, rates: { CODE: number } }
// Runs daily in GitHub Actions; the result is bundled into the app and served as the online fallback.
// Primary: fawazahmed0 Currency API (jsDelivr, then Cloudflare mirror). Fallback: open.er-api.com.
import { writeFile } from 'node:fs/promises';

const FAWAZ = [
  'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json',
  'https://latest.currency-api.pages.dev/v1/currencies/usd.json',
];
const ERAPI = 'https://open.er-api.com/v6/latest/USD';

const ISO = new Set(Intl.supportedValuesOf('currency'));

/** Uppercases codes, keeps real ISO 4217 currencies with positive finite values, pins USD = 1. */
function clean(raw) {
  const out = {};
  for (const [k, v] of Object.entries(raw ?? {})) {
    const c = k.toUpperCase();
    if (ISO.has(c) && typeof v === 'number' && Number.isFinite(v) && v > 0) out[c] = v;
  }
  out.USD = 1;
  return Object.fromEntries(Object.entries(out).sort(([a], [b]) => a.localeCompare(b)));
}

function valid(rates) {
  return Object.keys(rates).length > 100 && rates.INR > 0;
}

async function getJSON(url) {
  const res = await fetch(url, { headers: { 'cache-control': 'no-cache' }, signal: AbortSignal.timeout(20000) });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

async function fromFawaz(url) {
  const j = await getJSON(url);
  const rates = clean(j.usd);
  if (!valid(rates)) throw new Error(`only ${Object.keys(rates).length} rates`);
  const updated = new Date(`${j.date}T00:00:00Z`);
  if (Number.isNaN(updated.getTime())) throw new Error(`bad date ${j.date}`);
  return { base: 'USD', updated: updated.toISOString(), source: 'Currency API', rates };
}

async function fromERAPI() {
  const j = await getJSON(ERAPI);
  if (j.result !== 'success') throw new Error(`result ${j.result}`);
  const rates = clean(j.rates);
  if (!valid(rates)) throw new Error(`only ${Object.keys(rates).length} rates`);
  return {
    base: 'USD',
    updated: new Date(j.time_last_update_unix * 1000).toISOString(),
    source: 'Exchange Rate API',
    rates,
  };
}

const attempts = [...FAWAZ.map((u) => [u, () => fromFawaz(u)]), [ERAPI, fromERAPI]];
let out;
for (const [url, run] of attempts) {
  try {
    out = await run();
    break;
  } catch (e) {
    console.warn(`${url}: ${e.message}`);
  }
}
if (!out) throw new Error('All rate sources failed');

await writeFile(new URL('../rates.json', import.meta.url), JSON.stringify(out) + '\n');
console.log(`Wrote ${Object.keys(out.rates).length} rates from ${out.source}, updated ${out.updated}`);
