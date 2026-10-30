// Fetches USD-based rates (no API key) and writes rates.json in the app's format.
// Runs in GitHub Actions; the phone only ever reads the same-origin rates.json.
import { writeFile } from 'node:fs/promises';

const res = await fetch('https://open.er-api.com/v6/latest/USD');
if (!res.ok) throw new Error(`HTTP ${res.status}`);
const j = await res.json();
if (j.result !== 'success' || !j.rates?.INR) throw new Error('Unexpected payload');

const out = {
  base: 'USD',
  updated: new Date(j.time_last_update_unix * 1000).toISOString(),
  source: 'open.er-api.com (ExchangeRate-API)',
  rates: j.rates,
};
await writeFile(new URL('../rates.json', import.meta.url), JSON.stringify(out) + '\n');
console.log(`Wrote ${Object.keys(out.rates).length} rates, updated ${out.updated}`);
