# RdpFree

Dashboard: **https://rdpfree.projectkal.my.id** · Credit: **KallAncrit**

Windows RDP via **Tailscale private**, with a Next.js/Cloudflare dashboard and native XyDesk Remote API integration. No Pinggy, bore, ngrok, Serveo, localhost.run, Funnel, or public relay in the active workflow.

## Getting started

1. Sign in with your GitHub identity at `/login` (scope `read:user`). Signing in does not grant repository access.
2. Install the GitHub App separately at `/dashboard/connection`, selecting the allowed repositories. The service owner must first register the App on the hidden admin page `/admin/github-app`.
3. Create a repository from the template with the name of your choice. A regular operation token only gets Contents/Metadata read, Actions/Secrets write. The new manifest also requests Administration write for the repository-delete feature after owner confirmation; a delete-capable token is created separately. The App still cannot write to or clean the source folder. Manual templates still copy the web folder.
4. Fill in `RDP_PASSWORD` and `TAILSCALE_AUTH_KEY` through Setup. Connect your phone to the same tailnet. Do not share the auth key or password.
5. Configure the session in Settings, run from Home. Passwords are not printed, Base64-encoded, or stored as workflow artifacts. Reveal/copy remains via the authenticated dashboard vault.

`xyadmin` is the default username; `runneradmin` only if explicitly selected. The workflow changes Windows policies including UAC and the administrator account. Use a dedicated/disposable machine, not your primary work computer. Maximum job duration is 360 minutes including setup; setup time reduces the remaining session. GitHub-hosted sessions are not a PC gaming service and suspension is not guaranteed to be prevented.

## Games and media

The `/dashboard/games` page stores presets for SA-MP, Roblox, Minecraft Java and Bedrock and shows Windows status for the active session. Settings apply on the next run. Start/stop currently available are workflow sessions, not game processes on the desktop. Login, interactive installation, launch, and stopping a game are performed through XyDesk. Direct game process control from the dashboard is not yet available.

Game prep only runs on your dedicated self-hosted Windows runner labeled `self-hosted`, `Windows`, `X64`, `rdpfree`. Do not allow workflows/PRs from untrusted parties to use this runner. Finalize disconnects Tailscale but does not remove accounts, apps, or system changes on the self-hosted machine; reset the image after use.

- **SA-MP**: requires your own GTA SA. An installer/dependency or the presence of an EXE is not proof of successful server join.
- **Roblox**: official installer with verified signature. VMs may be rejected by Roblox. No BIOS spoofing, VM driver removal, or anti-cheat bypassing.
- **Minecraft Java**: official launcher, a licensed account and OpenGL/GPU support are still required.
- **Minecraft Bedrock**: Windows desktop with Store/Xbox. Windows Server is not supported by this setup. Store installation and login remain interactive.
- **Wallpaper**: the original XyVerse anime wallpaper from assets/wallpaper.jpg is applied to the user profile at logon, not only HKCU of the runner. The wallpaper is applied automatically with no yes/no choice or alternate URL. Clients must also enable desktop wallpaper.
- **Microphone**: the host allows RDP audio capture channel; XyDesk must enable input and request Android permission. Test via Windows Settings > Sound > Input. A device named “Remote Audio” under **Input** is recording, distinct from speaker output.

Statuses `installer_ready`, `installed_unverified`, `store_required`, `unsupported_environment`, and `requires_self_hosted` are not claims of successful playable state. Wallpaper/microphone and games have not passed end-to-end testing across Windows + Android devices.

## Updating older repositories

The new workflow is marked `# rdpfree-workflow-schema: 3`. The dashboard refuses dispatch to older workflows to avoid mis-sending new game/media parameters. Sync `.github/workflows/rdp-6h.yml`, the entire `scripts/`, and `assets/` from this repository. The GitHub App does not have permission to write source, so updates must be done by the repository owner. Saved `tunnel`/`all` settings are migrated to Tailscale; the old default SA-MP is disabled until the owner explicitly selects a dedicated machine.

## Source and access

- `.github/workflows/rdp-6h.yml`: Windows session + host preparation.
- `scripts/`: Windows scripts; `assets/`: wallpaper and configuration.
- `web-next/`: Next.js/OpenNext/Cloudflare dashboard in operation. The `web/`, `deploy/`, and old documentation folders are archives of previous implementations, not the current access configuration.
- Admin remains hidden, email/password login + Turnstile; it is not moved to GitHub login.
- Native API: see `web-next/docs/XYDESK-API.md`. Tokens are repository-bound and can be revoked. Old native OAuth tokens need to be re-created after the App split.
- Separate logins do not prevent suspension. For suspended tester accounts, reviews are only via GitHub Support; causes cannot be inferred from 404s or login patterns alone.

## Validation

Lint, TypeScript, OpenNext build, unit tests and mobile browser smoke tests are available/tested. PowerShell scripts are parsed with PowerShell 7; the parser is not a Windows installation test. Game UI tests use a mock API without starting runners or games. Real App installation requires owner approval. Do not treat these results as certification of game or audio end-to-end compatibility.

## Repo flow and deletion via the dashboard

Flow: create a repo from the template first → confirm “My repo has been created” → allow repository access via the GitHub App (Only select repositories) → pick the repo → fill secrets → start a session. Installing the App is authorization, not creating a repo or downloading a mobile app.

Repo deletion is available at `/dashboard/connection`, restricted to the GitHub login of the repository owner. Type the full name `owner/repo` and agree to the deletion impacts; active/queued workflows must stop. The service source repository is protected and XyDesk tokens cannot delete it. Registered Apps require Administration: Read and write and an update approval from the installation owner. Administration permission is broader than delete-only; GitHub does not provide a delete-specific scope for installation tokens. Regular tokens remain without Administration. Destructive testing uses mocks, not deleting user repositories.