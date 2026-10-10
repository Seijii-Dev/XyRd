# Creating or updating a RdpFree repository

Credit: KallAncrit. Follow the active [README](README.md).

1. Use the `xykal/XyRDP` template with your chosen repository name.
2. Enable Actions, then set `RDP_PASSWORD` and `TAILSCALE_AUTH_KEY` in Actions secrets or via the Setup dashboard.
3. Access only via Tailscale. Sign your phone/PC into the same tailnet and allow TCP 3389 in the tailnet ACL.
4. Choose settings and start a session. Do not print or save the password as a public artifact.
5. For game preparation, use a dedicated/disposable self-hosted Windows machine that is permitted, not GitHub-hosted gaming. Ensure the runner labels `self-hosted`, `Windows`, `X64`, `rdpfree` and read the system change effects in the README.

Older repositories need to sync workflow schema 2, scripts, and assets together. The app only has read access to the source so it cannot update those files automatically. The manual template also copies the web folder; owners may remove `web`, `web-next`, and `deploy` from the session repository if not needed.

GitHub login identity and GitHub App authorization are two separate processes. Installing/approving the App applies only to the repositories you choose. There is no guarantee against suspension or universal support for games/VMs.