# FX — offline currency converter (iOS PWA)

## Stack
Plain HTML/CSS/JS, no build step, no dependencies. Hosted on GitHub Pages (HTTPS is required for the service worker and iOS home-screen install).

## Files
- `index.html` / `styles.css` / `app.js` — the app. `convert(amount, from, to, rates)` is the only maths.
- `sw.js` — offline. App shell is cache-first; `rates.json` is network-first with cache fallback. **Bump `VERSION` on every shell change.**
- `rates.json` — USD-based rates, written only by `.github/workflows/rates.yml` (daily, via `scripts/fetch-rates.mjs`, source open.er-api.com). Never hand-edit.
- `tests/check.py` — headless iPhone 15 Pro run: light/dark screenshots, conversion assertion, offline reload. Uses `tests/fixture-rates.json` (fake round numbers).

## Loop
1. Edit. 2. `python3 tests/check.py` (screenshots in `tests/out/`). 3. Commit + push → Pages redeploys in ~1 min.

## Design constraints
- iOS Safari supports `backdrop-filter: blur() saturate()` but not SVG displacement filters, so "liquid glass" refraction is approximated with layered highlights. Chromium screenshots are a proxy; final check is on the device.
- Offline fallback order: network rates.json → SW cache → localStorage copy.
