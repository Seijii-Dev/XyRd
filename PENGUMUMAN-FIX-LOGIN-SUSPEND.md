# ANNOUNCEMENT — Fix Login on Every Refresh & Anti-Suspend (10 Oct 2026)

> Mandatory update for all fork users. Sync your fork now — the fix is already in `main` (`5c7df72` TOTAL REVISON of web login — anti login loop).

## 1. Login on every refresh — FIXED (no more annoying re-logins)

Previous issue: each browser refresh forced re-login.

Fix:
- Frontend now sends cookies with `credentials: 'include'` (previously not) → session `ghs`/`sid` (AES-256-GCM) are sent with every request
- Lifetimes extended **7 days → 30 days** (GitHub) and **12 hours → 30 days** (admin)
- Cache `localStorage: xyrdp_me_cache` — refresh still opens the dashboard first while checking in background

Your action (once after this update goes live on Vercel ~1 minute):
1. Open `xyrdp-dash.vercel.app` → if still asked to login, **Clear cookies** for the site (Chrome: lock icon → Cookies → remove `ghs` & `sid`) or `Ctrl+Shift+Del` → Cookies
2. Log in once → afterwards you’ll stay logged in for **30 days**, refresh won’t log you out anymore
3. Don’t change `SESSION_SECRET` in Vercel (≥32 char). If changed, all users are logged out.

## 2. Why Dashboard login can get suspended, while manual fork is safe?

| Method | Safe? | Why |
|---|---|---|
| **Manual fork on github.com** (`xykal/XyRDP` → `Use this template` → `Create new repository`) | **SAFEST** | Native GitHub action. Rate limits per your account. Workflow runs in your `you/RdpFree` repo using your token. Does not go through Vercel IP. |
| **Dashboard “Sign in with GitHub” (OAuth)** | Risky if spammed | Dashboard uses your token to `generate repo` + `set secrets` + `dispatch workflow` via **API from Vercel IP**. If many users click “Create Repo” + “Start” simultaneously within 1–2 minutes → detected as **automation spam / abuse** → flagged and suspended. |

Anti-suspend fixes on the dashboard (live):
- **Limit 2× Start per 5 minutes per user/IP** → if exceeded: `429 Wait Xs more`
- **Block dispatch if there is still a run `queued/in_progress`** → must `Stop` first
- All explained in `/panduan` new section

Safe ways to use the dashboard:
1. **Safest: fork manually first** on github.com (name it `RdpFree`), wait 1–2 minutes, then login to the dashboard (it will automatically use `your/RdpFree`)
2. Don’t spam “Create Repo” / “Start” — wait for the run to finish
3. Don’t create 5+ RDP repos in an hour with one account
4. Required secrets: `RDP_PASSWORD` (min 8) + `TAILSCALE_AUTH_KEY` (`tskey-auth-...` don’t share publicly). Optional: `GTA_SA_URL` for SAMP

## 3. How to sync your fork (gets the boost stuck & login fixes)

Fastest (web):
1. Open your fork `github.com/your/RdpFree` → button **Sync fork** → **Update branch** (or `Fetch upstream` if never done)
2. If the button is missing: `Settings` → `Actions` → `General` → ensure **Allow all actions** + **Workflow permissions: Read and write**
3. Check `Actions` tab → workflow `RdpFree — RDP 6 Jam` active (don’t Disable)

Via git (alternative):
```bash
git clone https://github.com/your/RdpFree.git
cd RdpFree
git remote add upstream https://github.com/xykal/XyRDP.git
git fetch upstream
git merge upstream/main
git push origin main
```

After sync, boost will no longer get stuck (previously `Get-ChildItem -Recurse` in `C:\Android` caused a 10-minute hang → now FAST `3m25s` proven on run #86). Check `Actions` → log ` Boost Storage`.

## 4. Black wallpaper & Microphone — FIX `1c0b668`

That black wallpaper is Windows Server default, not XyDesk. XyDesk only hosts the RDP — `mstsc` & XyDesk see the same session. The repo already includes `assets/wallpaper.jpg` + `wallpaper-win11.jpg` + `rdp-extras.json: wallpaper=true`. If still black:

- Client often disabled wallpaper:
  - `mstsc` → `Show Options` → `Experience` → check `Desktop background / Wallpaper`
  - `XyDesk Remote` → `Settings` → `Wallpaper` → **ON** (OFF = intentionally black to save ~30% bandwidth)
- Fix `1c0b668`: `setup-xydesk.ps1` now sets `fNoRemoteDesktopWallpaper=0` + `WallpaperStyle=10` via Policy (without writing `WinStations` so `3389` won’t stop) → next run wallpaper **will display** if client ON. New upload via dashboard `Settings → Upload Wallpaper` also applies immediately.

Microphone — POSSIBLE & NOW ENABLED:
- Host now: `fDisableAudio=0` + `fDisableAudioCapture=0` + `AudioQualityMode=2 (High)` + `AudioEndpointBuilder` running (Policy override). Log: `mic HP redirect active`.
- XyDesk: Phone → `Settings` → `Apps` → `XyDesk` → `Permissions` → Allow `Microphone` → XyDesk → `Settings` → `Enable Microphone ON` → in RDP open `mmsys.cpl` → `Recording` → `Remote Audio` → test with `Sound Recorder`.
- mstsc: edit `.rdp` add `audiomode:i:0` + `audiocapturemode:i:1` + `microphone:redirection:i:1`.

## 5. SAMP — Definitely Works (YouTube + Valid Links, works even if you’re unsure) — Latest Update

SAMP is free; you must have GTA SA yourself (keep a legal backup). Our script auto-installs SAMP client + DirectPlay + VC++ + DirectX anti-DxError + shortcut + firewall. You only provide GTA SA.

Method A — Easiest — Automatic via `GTA_SA_URL` (1 click):
1. Upload your portable GTA SA ZIP (contains `gta_sa.exe` + `models`/`data` ~2–4GB) to Google Drive → Share → `Anyone with the link` → Copy link `https://drive.google.com/file/d/1AbC.../view` (Dropbox `?dl=1` / MediaFire also OK)
2. Fork repo → `Settings` → `Secrets and variables` → `Actions` → `New secret` → Name `GTA_SA_URL` → Value paste the link (script auto-converts to `https://drive.google.com/uc?export=download&id=...` + handles confirm token)
3. Dashboard / Actions → `RdpFree — RDP 6 Jam` → `Run workflow` → `samp: ya`, `samp_extra: ya` → Start. Log ` Setup GTA SAMP` will `Download → extract to D:\Games\GTA San Andreas → SA-MP install → GTA SAMP.lnk shortcut on Desktop`.

Method B — Manual via RDP (if not using a link):
1. Start without `GTA_SA_URL` → connect via XyDesk/mstsc
2. Inside RDP open Chrome → download your portable GTA SA, or from your PC: `mstsc` → `Show Options` → `Local Resources` → `More` → check `Drives C:` → in RDP open `\\tsclient\C` → copy `GTA San Andreas` folder to `D:\Games\GTA San Andreas`
3. `GTA SAMP.lnk` shortcut is already on Desktop → double-click `samp.exe` → connect to server.

SAMP links are valid (script tries all mirrors automatically, no manual action needed):
- `https://files.sa-mp.com/sa-mp-0.3.7-R5-1-MP-install.exe` (official)
- `https://sa-mp.mp/downloads/` (new official mirror)
- `https://gta-multiplayer.cz/downloads/sa-mp-0.3.7-R5-2-MP-install.exe`
- Fallback scrapes `sa-mp.com/download.php` + `gta-multiplayer.cz` — if you want manual, open `https://sa-mp.mp/downloads/` in RDP → 0.3.7-R5-1 → install to `D:\Games\GTA San Andreas`.

Best YouTube tutorials:
- How to play GTA SAMP 2024 → https://www.youtube.com/watch?v=OHwnAK9SvFY
- SAMP Setup Guide (0:22 installation) → https://www.youtube.com/watch?v=GFWaoZnkRKM
- Search `cara pasang GTA SAMP` — essentially `GTA 1.0 US` + `sa-mp-0.3.7-R5-1-MP-install.exe` → point to GTA folder → samp.exe. Must be `GTA SA 1.0 US` (gta_sa.exe ~14MB), downgrade if Steam.

If still DxError: anti-DxError is implemented — script checks `d3dx9_43.dll` first, skips Jun2010 if already present, WARP fallback. Log `skip (already present)` is not a failure.

## 6. Other info

- Roblox Player won’t open: Hyper-V runner → anti-cheat block. Use **Roblox Studio** instead.
- Minecraft 20 fps: 2 vCPU + Mesa software renderer. Set `rdp-extras.json` → `lightweight_mode:true`, `translucent:false`, `win11_look:false`, use Sodium.

---
Credit: **KallAncrit** • RdpFree • Web not included in the fork — only the script repo.
Update `d5e554f` — Maximum disk cleanup + DirectX anti-DxError:
- `optimize-storage.ps1` default is **full debloat** (not light): Edge is **forcefully removed** (folders `Edge`/`EdgeCore` + all `*Edge*.lnk` shortcuts in `Public/Desktop`/`Default/Desktop`/`Start Menu` GONE), Unity Hub/Editor + R + OneDrive + Xbox + Clipchamp Appx GONE, plus `DeliveryOptimization cache`, `vcpkg`, `hostedtoolcache/stack` — frees **110–140GB** (log `Edge: SUCCESS removed ALL`). WebView2 is retained so apps won’t error. Chrome is not required anymore — Edge will still be removed if `full`.
- `setup-samp.ps1` DirectX **anti-DxError**: checks `d3dx9_43.dll` first (skip if present), extracts `Jun2010` with exit code + reads `C:\Windows\Logs\DirectX.log`, if `DxError` → fallback `WARP` (`skip` is not fatal, GTA SA still runs in software). So installs no longer fail.
- Default `RDP_USER` remains `xyadmin` (not `runneradmin`). Use `runneradmin` only if you set `RDP_USER=runneradmin` in the workflow (highest built-in). So **don’t use runneradmin** if you want separate users — keep the default.

Update `5c7df72` — TOTAL REVISION of web login (users already logged in still showed login):
- Backend `api/index.js`: `cookieHeader` Secure via `x-forwarded-proto` + `VERCEL_ENV` (previously sometimes not sent), `ghUserDebug` reason (`no_cookie`, `unseal_failed`, `expired`), `/auth/status` returns `debug` + sliding refresh `ghs` 30d if remaining <7d (previously expired immediately on logout), all `Set-Cookie` use `req`.
- Frontend `index.html`: `boot()` timeout 7s + retry 2x, fallback `localStorage 12h`, do not immediately `showLogin` on network 500, `api()` `credentials:include` + `me_at`, `showLogin` displays debug in `ghNote`.

Live: `xyrdp-dash.vercel.app` (Vercel `5c7df72`) + workflow `1c0b668` wallpaper/mic + `d5e554f` disk/DirectX + `5c7df72` web total revision.