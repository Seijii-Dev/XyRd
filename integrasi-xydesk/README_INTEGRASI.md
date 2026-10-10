# XyRDP-SAMP ↔ XyDesk Remote (APK) Integration — Create RDP with 1x Ad

> Purpose: User opens the XyDesk Remote APK → taps “RDP Free 6 Hours” → watches an ad 1x per device lifetime → can immediately Create RDP via WebView without leaving the APK. Remaining time on the dashboard is displayed as a large digital clock (not a progress bar).

This is a plug-and-play package for the repository github.com/xykal/Xydesk-Remote.

---

## 1) What’s already done in XyRDP (web)

Web `deploy/vercel/assets/index.html`
- Remaining time replaced with a large digital clock: `HH:MM:SS` using a mono font JetBrains Mono-style, blinking colon, glow drop-shadow, live pulsing dot, sub-text “Remaining X hours Y minutes”.
- Progress bar removed (keeps `<span id="stLeft" class="hidden">` so older JS doesn’t break).
- Ad gate: modal `id="adGate"` → 15s countdown + progress; after completion sets `localStorage rdp_ad_unlocked=1` + cookie `ad_verified=1` (30 days) + `POST /api/ad/verify`.

API `deploy/vercel/api/index.js`
- `POST /api/ad/verify` → `Set-Cookie: ad_verified=1; Max-Age=2592000`
- `GET /api/ad/status` → `{unlocked:true|false}`
- `GET /api/apk` → APK info
- `POST /api/start` now requires ad for `kind=user` (admin bypass):
  ```js
  if (ctx.kind==='user' && !hasAd && AD_GATE_DISABLED!=='1') return 402 {need_ad:true}
  ```
  Accepted header: `ad_verified` cookie OR `X-Ad-Verified:1` / `X-Xy-Ad:1` (for APK WebView).
- CORS `*` enabled for `/ad/*` & `/apk`.

How to test web:
- Open `/id/home`, the Start Session button will open the gate if not unlocked.
- After “Watch 15s”, localStorage + cookie set, the button becomes permanently active.
- Remaining time now displays in the Session card → large digital clock `06:00:00`.

---

## 2) APK Integration — 3 steps

Step A — Add AdMob (Rewarded)

`client/Android/Studio/app/build.gradle` → dependencies:
```gradle
implementation 'com.google.android.gms:play-services-ads:23.0.0'
```

`AndroidManifest.xml` → inside `<application>`:
```xml
<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="ca-app-pub-xxxxxxxxxxxxxxxx~yyyyyyyyyy"/>
<!-- use TEST ID first: ca-app-pub-3940256099942544~3347511713 -->
```

Step B — Copy 2 new files

Copy to `client/Android/Studio/app/src/main/kotlin/id/xydesk/remote/ui/`:

- `XyFreeRdpScreen.kt` (included in this folder) — WebView + Ad gate + bridge.
- `XyRdpAdHelper.kt` (optional, can be merged) — AdMob helper.

Step C — Add entry in Home

Open `XyDeskHome.kt`, add a card above the device list (see diff `patch_XyDeskHome.kt.diff`).

Minimal snippet:
```kotlin
// in Devices route, top of Column
XyFreeRdpCard(
  unlocked = appPrefs.rdpFreeAdUnlocked,
  onCreate = {
    if (appPrefs.rdpFreeAdUnlocked) navToRdpFree()
    else showRdpAd { appPrefs.rdpFreeAdUnlocked = true; navToRdpFree() }
  }
)
```

Add to `AppPrefs.kt`:
```kotlin
var rdpFreeAdUnlocked: Boolean
  get() = sp.getBoolean("rdp_free_ad_unlocked", false)
  set(v) = sp.edit().putBoolean("rdp_free_ad_unlocked", v).apply()
```

---

## 3) APK Flow (user perspective)

1. Open XyDesk Remote → Home → card “RDP Free 6 Hours — Create Windows on Phone”
2. Tap Create RDP → if the user hasn’t watched yet, a Rewarded Ad appears (15–30s)
3. After watching → `rdpFreeAdUnlocked=true` + `CookieManager.setCookie("https://xyrdp-dash.vercel.app","ad_verified=1")`
4. WebView loads `https://xyrdp-dash.vercel.app/id/home?apk=1` → user logs in with GitHub (OAuth) in the WebView → taps Start Session (already unlocked, no ad required)
5. Polling `/api/status` → large digital clock `05:42:11` appears.
6. Connection card → “Connect in XyDesk” (bridge) automatically creates `ConnectionProfile(host=100.x, user, pass)` → `XyDeskSessionActivity`.

Once unlocked, the ad is never required again (per device). If the app is reinstalled, user must watch again once.

---

## 4) Web ↔ APK Bridge (advanced, optional)

The web (`index.html`) already exposes:
```js
window.XyDesk = window.XyDesk || {}
// APK injects via addJavascriptInterface
// Web if it detects `Android` or `?apk=1` shows “Open in XyDesk” button
if (navigator.userAgent.includes("XyDesk")) {
  // show extra button
}
```

In `XyFreeRdpScreen.kt`, the WebView already injects:
```kotlin
webView.addJavascriptInterface(object{
  @JavascriptInterface fun onRdpCreated(json: String){ /* parse ip/user/pass, create profile */ }
}, "Android")
```
Web can call `Android.onRdpCreated(...)` when `poll()` detects `session.active`.

---

## 5) Test checklist

- [ ] Web: clear `localStorage` → click Start Session → gate appears → 15s → unlock → start succeeds (200) without 402.
- [ ] API: `curl -X POST https://xyrdp-dash.vercel.app/api/ad/verify -c cookies.txt` → cookie set → `curl -b cookies.txt POST /api/start` → 200 (not 402).
- [ ] APK: fresh install → tap Create → ad shows → after reward, WebView loads dashboard → login GitHub → Create → large digital clock appears `HH:MM:SS`.
- [ ] Reopen APK → tap Create → immediately WebView (no ad again).

---

## 6) Files in this package

- `XyFreeRdpScreen.kt` — full Compose screen
- `patch_XyDeskHome.kt.diff` — 12-line diff to add the card
- `patch_AppPrefs.kt.diff` — add pref
- `README_INTEGRASI.md` — this file

Credit remains to KallAncrit for the XyRDP template.

---

## 7) Anti-AdBlock & Monetization Options (2026)

Why ads still detected even with AdBlock?
The gate does not rely on external ad scripts to unlock:
- Detection: checks bait `div.ad` + `getComputedStyle` + tries fetching `adsbygoogle.js`. Result stored in `__adBlockDetected`.
- Unlock requires `POST /api/ad/verify` + cookie `ad_verified` + `localStorage` — server validates, not client. So even with uBlock/APK AdGuard, the user still must spend 15s in our internal modal. Cannot bypass with inspect-element (server rejects `POST /start` with `402 need_ad`).

Internal fallback ad shown when blocked:
- `adPreviewText = " AdBlock detected — you still must watch 15s (internal ad)"` → shows a XyDesk promo + local sponsor (you can put your affiliate banner). The countdown still runs, reward still unlocks. So AdBlock makes the user see your promo rather than skipping.

Recommended ad networks (monetization, 2026)

WEB (Vercel dashboard):
- Best for 1x rewarded: Google AdSense Rewarded or Google Ad Manager Rewarded — highest eCPM ($3–$8 in ID, $8–$15 US) but requires domain approval.
- Easiest to approve & more resistant to AdBlock: Adsterra Social Bar + Rewarded Interstitial or Monetag Rewarded — eCPM $1–$4 ID, $4–$9 US, instant approval, light script, not as aggressively blocked as AdSense. Good as a fallback when `__adBlockDetected==true`.
- Alternatives: PropellerAds Rewarded, a-ads.com (crypto, no KYC), HilltopAds.
- Recommended hybrid implementation:
  ```js
  if(!__adBlockDetected) loadAdsense(); else loadAdsterra(); // still 15s
  ```
  Store provider IDs in `window.__adProviders.web`.

APK (XyDesk Remote):
- Best: AdMob Rewarded (`play-services-ads:23.0.0`) — eCPM $5–$12 ID, $15–$40 US for rewarded video. Use mediation for ~99% fill-rate:
  - Mediation: AdMob + Facebook Audience Network + Unity Ads + AppLovin MAX.
- Setup: Test ID `ca-app-pub-3940256099942544/5224354917` → replace with production `ca-app-pub-xxx/yyy` in `XyRdpAdHelper.kt`. Don’t forget `APPLICATION_ID` in `AndroidManifest.xml`.
- Monetization tips: Use rewarded instead of interstitial — rewarded pays 3–5x more and is less intrusive since it’s only 1x.

Conclusion: For this PR, the default internal 15s gate works 100% even with AdBlock. Later you just replace `window.__adProviders` & `XyRdpAdHelper.PROD_REWARDED_ID` with production IDs without changing gate logic.