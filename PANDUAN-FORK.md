# Creating or updating a RdpFree repository

Credit: KallAncrit. Follow the active [README](README.md).

1. Create or select the repository that will hold the workflow.
2. Enable GitHub Actions, then set `RDP_PASSWORD` and `TAILSCALE_AUTH_KEY` through the Setup dashboard or Actions secrets.
3. Use private Tailscale access. Sign your phone/PC into the same tailnet and allow TCP 3389 in the tailnet ACL.
4. Configure the session in Settings and start it from Home. Never print or save the password as a public artifact.
5. Use a dedicated runner if you choose self-hosted mode. Do not run workflows from untrusted pull requests on a machine that changes Windows policies or applications.

Older repositories should synchronize `.github/workflows/rdp-6h.yml`, `scripts/`, and `assets/` together. The app has read-only source access and cannot update those files silently. Codex CLI and the standalone Antigravity IDE are installed automatically by the extras step; account sign-in remains interactive after connecting.

GitHub identity login and GitHub App authorization are separate processes. Install the App only for repositories you intend to connect.
