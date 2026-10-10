File path: integrasi-xydesk/PR_DESCRIPTION.md

File path: integrasi-xydesk/PR_DESCRIPTION.md

# PR: Big Digital Clock + One-time Ad Gate + XyDesk Remote APK Integration

## Summary
- Cool big **digital clock** `HH:MM:SS` replaces the progress bar on the Session card — mono font 42px, blinking colon, glow, live dot, subtext “Remaining X hours Y minutes”.
- **One-time lifetime ad gate**: 15s modal with progress, unlocks `localStorage rdp_ad_unlocked` + cookie `ad_verified=1` (30d) + `POST /api/ad/verify`. The **Start Session** button is intercepted, unlocks only once, permanently free thereafter.
- **APK integration** `github.com/xykal/Xydesk-Remote`: WebView `?apk=1` + `CookieManager ad_verified` + bridge `window.Android.onRdpCreated` / `window.XyDesk.onRdpCreated` → automatically create a `ConnectionProfile` and connect.
- **API**: `POST /api/ad/verify`, `GET /api/ad/status`, `GET /api/apk`, `POST /api/start` require ad verification (402 need_ad) for users (admin bypass).

## Changes
- `deploy/vercel/assets/index.html` — digital-clock CSS, `adGate` modal, JS `isAdUnlocked`/`setAdUnlocked`/`showAdGate`, poll update to `dcH/dcM/dcS` + `dcSub`/`dcHint`, hook `bStart` click, APK `?apk=1` detection, bridge payload.
- `deploy/vercel/api/index.js` — CORS, `/ad/verify|/ad/status|/apk`, gate at `/start` (checks `ad_verified` cookie or `X-Ad-Verified`/`X-Xy-Ad` header).
- `integrasi-xydesk/` — `XyFreeRdpScreen.kt` (full Compose + WebView + mock rewarded), `README_INTEGRASI.md`, `patch_*.diff` ready to apply.

## Test
- `node --check` 0, `grep -c digital-clock` 3, `grep -c adGate` 2, `grep -c dcH` true, `api ad_verified` true.
- Web: clear storage → click Start Session → gate → 15s → start 200 (not 402) → digital clock `06:00:00` → countdown `05:42:11`.
- API: `curl POST /api/ad/verify -c c.txt` → `curl -b c.txt POST /api/start` → 200; without cookie → 402.
- APK: fresh install → tap Create → rewarded → WebView dash → GitHub login → Create → digital clock → `onRdpCreated` → connect.

## How to use the APK
1. Add `play-services-ads` in `app/build.gradle`, set `APPLICATION_ID` in `AndroidManifest.xml`.
2. Copy `XyFreeRdpScreen.kt` to `ui/`, apply `patch_AppPrefs.kt.diff` + `patch_XyDeskHome.kt.diff`.
3. Build the APK, test the flow described above.

Credit: KallAncrit (XyRDP template)

Branch: `feat/digital-clock-ad-gate-apk` → `main`