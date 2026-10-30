// State: selected currencies, the row being typed in, and its amount — persisted locally.
const STORE = 'fx-state-v1';
const RATES_KEY = 'fx-rates-v1';
const DEFAULT = { list: ['INR', 'USD', 'EUR', 'AED', 'GBP'], active: 'USD', amount: '1' };

const state = { ...DEFAULT, ...safeParse(localStorage.getItem(STORE)) };
let rates = safeParse(localStorage.getItem(RATES_KEY)); // { base, updated, rates: {CCY: perBase} }

const names = new Intl.DisplayNames(['en'], { type: 'currency' });
const rowsEl = document.getElementById('rows');
const statusEl = document.getElementById('status');
const tpl = document.getElementById('row-tpl');

function safeParse(s) { try { return JSON.parse(s) || undefined; } catch { return undefined; } }
function save() { localStorage.setItem(STORE, JSON.stringify(state)); }

export function convert(amount, from, to, r) {
  if (!r || !r.rates[from] || !r.rates[to]) return NaN;
  return amount / r.rates[from] * r.rates[to];
}

function fmt(n, ccy) {
  if (!isFinite(n)) return '—';
  const digits = Math.abs(n) >= 1000 ? 2 : Math.abs(n) >= 1 ? 2 : 4;
  return new Intl.NumberFormat('en-IN', { maximumFractionDigits: digits }).format(n);
}

function parse(str) { return parseFloat(String(str).replace(/,/g, '')) || 0; }

function render() {
  rowsEl.replaceChildren(...state.list.map(ccy => {
    const node = tpl.content.firstElementChild.cloneNode(true);
    node.dataset.ccy = ccy;
    node.querySelector('.ccy').textContent = ccy;
    node.querySelector('.name').textContent = names.of(ccy);
    const input = node.querySelector('.amount');
    input.addEventListener('focus', () => { state.active = ccy; input.value = state.amount; input.select(); update(); });
    input.addEventListener('input', () => { state.amount = input.value; save(); update(); });
    rowsEl.appendChild(node);
    return node;
  }));
  update();
}

function update() {
  const amt = parse(state.amount);
  for (const row of rowsEl.children) {
    const ccy = row.dataset.ccy;
    const input = row.querySelector('.amount');
    const isActive = ccy === state.active;
    row.classList.toggle('active', isActive);
    if (isActive) { if (document.activeElement !== input) input.value = state.amount; }
    else input.value = fmt(convert(amt, state.active, ccy, rates), ccy);
  }
  statusEl.textContent = rates ? `Rates ${new Date(rates.updated).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })}` : 'No rates yet';
}

async function refreshRates() {
  try {
    const res = await fetch('rates.json', { cache: 'no-store' });
    if (!res.ok) throw new Error(res.status);
    const r = await res.json();
    if (r && r.rates && Object.keys(r.rates).length) {
      rates = r;
      localStorage.setItem(RATES_KEY, JSON.stringify(r));
      update();
    }
  } catch { /* offline: keep cached rates */ }
}

if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js');
render();
refreshRates();
