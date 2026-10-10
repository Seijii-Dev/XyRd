# RdpFree native API v1

Base URL: `https://rdpfree.projectkal.my.id/api/v1`

## Authentication

1. Log in on the website. Open `/dashboard/devices` (XyDesk menu).
2. Create a device token. Copy it once into XyDesk Remote.
3. Every native request sends `Authorization: Bearer <device-token>`.
4. Store the token in Android Keystore-backed CredentialVault. Do not log it, put it in an intent/URL, or store it in ordinary preferences.
5. Tokens expire after 30 days. Create a replacement in the website. Revoke lost devices from the same page or use POST `/device/revoke` to revoke self.

Device tokens are random 256-bit credentials; D1 stores only their SHA-256 hashes. The associated GitHub credential is encrypted with the server session key. Device scope is repository read, settings read/write, workflow list/start/cancel for the issuing account's fixed repository. Tokens cannot access admin routes, mint other tokens, or manage other devices. Password changes do not revoke independently issued devices: explicitly revoke devices if compromised.

Admin login is **not** an API login method. Admin email/password + Turnstile is browser-only and has no OAuth fallback. Do not embed admin credentials, GitHub PATs, or Turnstile secrets into the APK.

## Endpoints

| Method | Endpoint | Behavior |
|---|---|---|
| GET | `/repository` | Repository URL, default branch, permissions |
| GET | `/repository?path=scripts` | Repository folder/file content; browser only previews small files |
| GET | `/settings` | `{repo, inputs, choices, workflow}` |
| PUT | `/settings` | `{ "inputs": { ... } }`; validates and persists settings for the next run |
| GET | `/status` | Active/latest run, phase, current-session timestamps and connection |
| GET | `/runs` | Up to 30 recent runs for `rdp-6h.yml` |
| POST | `/runs` | `{ "confirm": true }`; dispatches using saved settings and repo's default branch |
| GET | `/runs/{id}/jobs` | Job/step status. Full textual logs are linked to GitHub on the website |
| POST | `/runs/{id}/cancel` | `{ "confirm": true }`; cancels a run only if it belongs to `rdp-6h.yml` |
| POST | `/device/revoke` | Revokes the requesting device token |

Browser-only `/devices`: GET lists device metadata, POST `{name}` issues a token, DELETE `{id}` revokes. Mutating browser requests require an exact same-origin `Origin` header and a valid HttpOnly session. Bearer devices cannot call these endpoints.

### Connection response example (illustrative, not an actual active RDP)

```json
{
  "repo": "xykal/XyRDP",
  "phase": "ready",
  "active": true,
  "run": { "id": 123, "status": "in_progress", "html_url": "https://github.com/xykal/XyRDP/actions/runs/123" },
  "session": { "hostname": "rdpfree", "started_at": "2026-10-10T18:00:00Z", "expires_at": "2026-10-10T18:30:00Z", "username": "xyadmin" },
  "connection": { "host": "example.invalid", "port": 3389, "username": "xyadmin", "password_required": true, "transport": "tunnel" },
  "server_time": "2026-10-10T18:05:00Z"
}
```

`phase` is `stopped`, `preparing`, or `ready`. Connection is null unless the status file's run ID matches a live run and the session has not expired. Poll every 15 seconds while the screen is active; back off on errors. Recheck status before connecting. `ready` means a current workflow published connection data, not that this API has independently tested RDP reachability.

RDP_PASSWORD is a GitHub Actions secret and **cannot be retrieved**. Prompt for it in the app. Do not publish it in status JSON. API HTTPS is the control plane, not a TCP relay. XyDesk connects to the returned host/port; a Tailscale connection also requires the appropriate network client.

## Settings

Fields mirror `.github/workflows/rdp-6h.yml`:
`durasi_menit`, `hostname`, `rdp_user`, `akses`, `tunnel_provider`, `storage_boost`, `debloat`, `samp`, `samp_extra`, `gta_sa_url`, `win11`, `xydesk`, `ekstra`, `grafis`, `wallpaper_url`.

Get allowed choice values from `/settings`, do not invent input names. Default user `xyadmin`; optional `runneradmin` is accepted. Workflow job timeout is 360 minutes including setup, so a requested 360-minute session is not a guarantee of 360 minutes of usable desktop time. Settings do not alter already running jobs.

Dispatch requires repository write permission, no active/queued run, and required Actions secrets (`RDP_PASSWORD`, plus Tailscale/ngrok keys when selected). Two start attempts per 5 minutes; an atomic 90-second repository lock prevents duplicate dispatch during GitHub eventual consistency. The application does not restart sessions automatically or promise protection against GitHub account enforcement. Use Actions in accordance with account policies and quotas.

## Errors and retry rules

Errors are JSON `{error: "message"}` with `Cache-Control: private, no-store`.
- 400 invalid settings/confirmation or missing repository secrets.
- 401 session/token invalid or expired; ask for a new token.
- 403 insufficient permission, wrong origin, or restricted endpoint.
- 404 repository/workflow/file not found.
- 409 run active or dispatch lock held.
- 429 start/token issuance throttled; wait before trying again.
- 502/503 GitHub/network/service error; show message and preserve the user's screen.

Never automatically retry POST `/runs` after an ambiguous network error. Refresh `/status`/`runs` first and require a new explicit user action. No wildcard browser CORS: native HTTPS clients do not need CORS.

## Repository onboarding update

`GET /setup` exposes selected repository readiness. When no repository/workflow exists, `/status` returns HTTP 200 with `phase: "setup_required"`, `active: false`, null run/connection, and a `setup` object. Direct the user to `https://rdpfree.projectkal.my.id/dashboard/setup`; do not start a workflow in this state.

Browser-only `POST /setup` actions: `create` (`name`, `private`, `confirm:true`), `connect` (`name`), `finish`. `finish` is independently retryable while GitHub template generation propagates. The selected repo is persisted server-side and no longer assumes `/XyRDP`. Existing native tokens retain their originally granted repo; token issuance now requires a ready repository.

Browser-only POST `/secrets` and POST/DELETE `/credentials` do not accept bearer device tokens. Native clients never receive the dashboard's stored password copy; prompt locally for RDP_PASSWORD. Website password controls support show/hide/copy and optional encrypted storage.

## GitHub App migration

Identity login and repository authorization are now separate. Users must complete GitHub App installation and choose a permitted personal-account repo at `/dashboard/connection` before issuing a device token. A 409 response can mean the dashboard identity is valid but repository installation/selection is incomplete; do not treat it as a lost login cookie.

Previously issued non-admin device tokens carrying OAuth grants are no longer accepted. Ask the user to complete app connection and create a replacement token. New tokens remain pinned to the chosen repo and exchange server-side for short-lived, repo-restricted installation tokens on each call. Admin-issued device grants are unchanged. No API exposes GitHub OAuth tokens, app private keys or installation access tokens to XyDesk.

## Schema 2: Tailscale, media, game preparation

Only `tailscale` is accepted for `akses`; `tunnel_provider` is removed. Persisted old settings migrate on read. `runner` is `github` or `self-hosted`; game preparation is rejected on hosted dispatch. New yes/no fields: `wallpaper`, `microphone`, `roblox`, `minecraft_java`, `minecraft_bedrock`. Existing `samp`, `gta_sa_url`, `samp_extra` remain. Self-hosted machine must be dedicated/disposable with labels `self-hosted`, `Windows`, `X64`, `rdpfree`.

Status optionally includes `games`, `media`, `game_environment` only for the matching active, unexpired run. Connection always uses Tailscale IP + port 3389. Media reports configuration, not verified end-to-end functionality; game status reports preparation, not playability. No API for launching/stopping desktop game processes exists yet. Settings affect the next workflow run, not the active desktop.

Dispatch checks workflow schema 2 and returns 409 for old source. Repository owners must update workflow, scripts and assets manually; Contents read permission is intentionally insufficient to do it silently. No password/Base64 credential artifacts or logs are produced by the new workflow.


## Onboarding and repository deletion (2026-10-10)

User sequence: identity login → create repo from template → allow the GitHub App to access that repo → choose repo → fill secrets → start session. The "My repo has been created" button only navigates the guide, not server verification. Repository selection verifies the workflow via GitHub.

Delete feature is available at `/dashboard/connection` for the browser session of the personal-account repository owner, not for service admin login or XyDesk tokens. Server confirmation is valid for 5 minutes, bound to subject + repo + GitHub ID, single-use; the user must type the full name and agree to the impact. Active/queued workflows block deletion. Service source repositories are protected. After GitHub confirms deletion, mapping, settings, repo vault and all of the user's XyDesk tokens are cleaned up; login/App installation remains. No real repositories are deleted during testing; destructive API tests use mocks.

Permission change: the old note "does not request Administration" applied to versions before the delete feature. The new manifest requests Administration write in addition to previous permissions. For already-registered Apps, the owner must add Administration: Read and write in Permissions & events, then the installation owner approves the update. GitHub does not provide delete-only permission; Administration includes authority to manage other repos as well. Use Only select repositories. Regular operation tokens still only have Contents/Metadata read, Actions/Secrets write; Administration is only requested for a temporary token restricted to one repo during the delete operation and revoked afterward. Contents remains read: this feature does not add source write capability.

### Schema 3 / automatic XyVerse wallpaper

The host now always uses the original `assets/wallpaper.jpg` anime XyVerse image. `wallpaper` and `wallpaper_url` are removed from settings and workflow dispatch; legacy client values are ignored. Sync workflow + scripts + assets together. Host policy permits wallpaper, but the RDP client must also negotiate `+wallpaper`. Existing connected sessions need disconnect/reconnect and existing desktop profiles may need sign out/sign in. A configuration or CLI test is not a Windows/Android visual acceptance test.