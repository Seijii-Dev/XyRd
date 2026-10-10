# Changelog XyRDP-SAMP Mod

## v1.0 — 2026-10-09 — Initial SAMP + Storage Booster Mod
- **Added `scripts/optimize-storage.ps1`**: frees 45–75GB (old Android/Haskell/CodeQL/dotnet/cache)
- **Added `scripts/setup-samp.ps1`**: auto install GTA SAMP 0.3.7-R5 + DirectX9 + VC++ + DirectPlay + compat + shortcut
- **Modified `.github/workflows/rdp-6h.yml`**: added inputs `storage_boost`, `samp`, `samp_extra`, `gta_sa_url` + 3 new steps
- **Modified `scripts/lib-common.ps1`**: added defaults `storage_boost`, `samp`, `samp_extra`
- **Modified `assets/rdp-extras.json`**: added SAMP keys
- **Added `README.md`**: full guide + storage solved + fork setup
- **Added `PANDUAN-FORK.md`**: fork-specific step-by-step
- Tested on `windows-2025` image Oct 2026: before 72GB free → after 128GB free

### Known Limitations
- GTA SA requires legal files owned by the user (BYOG)
- WARP llvmpipe = 20–35fps on low setting
- Pinggy tunnel 60 minutes → auto renew via keepalive (new address)