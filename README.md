# RdpFree

Dashboard: **https://rdpfree.projectkal.my.id** · Credit: **KallAncrit**

Windows RDP through **private Tailscale**, with a Next.js/Cloudflare dashboard and native XyDesk Remote API integration. The active workflow uses the GitHub `windows-2025` runner target and does not use public relay tunnels.

## Getting started

1. Sign in at `/login` with GitHub.
2. Install the GitHub App at `/dashboard/connection` and select the repository to control.
3. Set `RDP_PASSWORD` and `TAILSCALE_AUTH_KEY` through Setup. Keep your phone/PC on the same Tailscale network.
4. Configure the session in Settings and start it from Home.

The default RDP username is `xyadmin`. The workflow can change Windows policies and the administrator account, so use a dedicated or disposable machine. The maximum job duration is 360 minutes including setup. Passwords are not printed to logs or stored as workflow artifacts.

## Included features

- Windows 11 appearance settings on the `windows-2025` runner.
- Private Tailscale access to RDP port 3389.
- XyDesk Remote host setup with audio and microphone support.
- Automatic XyVerse wallpaper, optional desktop extras, debloat, and coding editors.
- Repository-bound dashboard and native API device tokens.

**Games and storage boost have been removed.** They are no longer available in the workflow, dashboard, API settings, scripts, or documentation.

## Source layout

- `.github/workflows/rdp-6h.yml`: Windows session workflow.
- `scripts/`: Windows setup and lifecycle scripts.
- `assets/`: wallpaper and configuration.
- `web-next/`: active Next.js/OpenNext/Cloudflare dashboard.
- `web/` and `deploy/`: legacy archived implementations.

## Updating older repositories

Synchronize the workflow, the complete `scripts/` directory, and `assets/` together. Older settings containing removed options are migrated where possible, but new requests must use the current settings schema.

## Validation

Run `npm run lint` and `npm run build` from `web-next`. PowerShell scripts require PowerShell 7 for parser checks; parsing is not a substitute for testing on a Windows machine.
