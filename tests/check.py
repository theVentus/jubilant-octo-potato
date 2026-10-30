"""Headless iPhone check: renders light/dark, verifies conversion, then reloads offline.
Usage: python3 tests/check.py   (serves the app itself on :8765; screenshots -> tests/out/)"""
import http.server, socketserver, threading, functools, pathlib, sys
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'out'; OUT.mkdir(exist_ok=True)
FIXTURE = (ROOT / 'tests' / 'fixture-rates.json').read_text()
PORT = 8765

class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass

srv = socketserver.TCPServer(('127.0.0.1', PORT), functools.partial(Quiet, directory=str(ROOT)))
threading.Thread(target=srv.serve_forever, daemon=True).start()
fails = []

def check(cond, msg):
    print(('PASS ' if cond else 'FAIL ') + msg)
    if not cond: fails.append(msg)

with sync_playwright() as p:
    b = p.chromium.launch()
    for scheme in ('light', 'dark'):
        ctx = b.new_context(**p.devices['iPhone 15 Pro'], color_scheme=scheme)
        ctx.route('**/rates.json', lambda r: r.fulfill(body=FIXTURE, content_type='application/json'))
        pg = ctx.new_page()
        errors = []; pg.on('pageerror', lambda e: errors.append(str(e)))
        pg.goto(f'http://127.0.0.1:{PORT}/'); pg.wait_for_timeout(600)

        usd = pg.locator('.row[data-ccy=USD] .amount')
        usd.click(); usd.fill('10'); pg.wait_for_timeout(100)
        inr = pg.locator('.row[data-ccy=INR] .amount').input_value()
        check(inr == '800', f'[{scheme}] 10 USD -> INR shows 800 (got {inr!r})')
        check(not errors, f'[{scheme}] no JS errors {errors}')
        pg.screenshot(path=str(OUT / f'{scheme}.png'))

        if scheme == 'light':  # offline reload after SW install
            pg.evaluate('navigator.serviceWorker.ready'); pg.reload(); pg.wait_for_timeout(500)
            ctx.unroute('**/rates.json'); ctx.set_offline(True)
            pg.reload(); pg.wait_for_timeout(600)
            rows = pg.locator('.row').count()
            gbp = pg.locator('.row[data-ccy=GBP] .amount').input_value()
            check(rows == 5, f'offline reload renders rows ({rows})')
            check(gbp == '5', f'offline conversion uses cached rates (GBP {gbp!r})')
            pg.screenshot(path=str(OUT / 'offline.png'))
        ctx.close()
    b.close()
srv.shutdown()
sys.exit(1 if fails else 0)
