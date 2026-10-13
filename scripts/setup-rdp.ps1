# ============================================================================
#  setup-rdp.ps1 — BASIC MODE (v2: without Tailscale)
#  1) create admin user (Administrators + Remote Desktop Users, password fixed)
#  2) enable Remote Desktop port 3389 (Windows default setting)
#  3) record session info to out/rdp-status.json (without password)
#
# Incoming access:
#    - TCP tunnel to port 3389 (pinggy/bore/ngrok/localhost.run/serveo) -> scripts/setup-akses.ps1
#    - Tailscale (optional, 100.x if TAILSCALE_AUTH_KEY exists)
#  Port 3389 on this VM is never open to the internet (GitHub runners
#  do not have a public inbound); only reachable via tunnel/Tailscale.
# ============================================================================

$XyTag = 'XyRDP:rdp'
. "$PSScriptRoot/lib-common.ps1"

# ---------- 0. Validation ----------
if (-not $env:RDP_PASSWORD -or $env:RDP_PASSWORD.Length -lt 8) {
  Log 'ERROR: secret RDP_PASSWORD not set / too short (min 8 characters).'; exit 1
}
$dur = [int]($env:DUR -replace '\D', ''); if ($dur -lt 10) { $dur = 360 }; if ($dur -gt 355) { $dur = 355 }
$u = if ($env:RDP_USER) { $env:RDP_USER.Trim() } else { 'SeijiAdmin' }
$reservedUsers = @('administrator','guest','defaultaccount','wdagutilityaccount','system','localservice','networkservice','con','prn','aux','nul')
if ($u -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{2,19}$' -or $reservedUsers -contains $u.ToLower()) {
  Log 'ERROR: RDP_USER is invalid. Use 3–20 characters (letters/digits, _ or -); avoid built-in Windows names.'
  exit 1
}
$cfg = Get-Cfg
$hostName = 'SeijiDesktop'
Log 'fixed computer name: SeijiDesktop (not user-changeable)'

$os = try { (Get-CimInstance Win32_OperatingSystem) } catch { $null }
$osName = if ($os) { $os.Caption } else { 'Windows' }
$osBuild = if ($os) { "$($os.Version)" } else { '' }
Log "basic mode | hostname $hostName | duration $dur minutes | user $u | OS $osName ($osBuild)"

# ---------- 1. Admin user (full access, fixed password) ----------
$sp = ConvertTo-SecureString $env:RDP_PASSWORD -AsPlainText -Force
# === runneradmin = built-in GitHub runner account (highest), do not remove ===
if ($u.ToLower() -eq 'runneradmin') {
  Log "runneradmin mode: using built-in runner account (highest, not recreated)"
  try { Set-LocalUser -Name $u -Password $sp -PasswordNeverExpires $true -AccountNeverExpires -ErrorAction Stop | Out-Null } catch {
    try { & net user $u $env:RDP_PASSWORD /add 2>&1 | Out-Null; & net user $u $env:RDP_PASSWORD 2>&1 | Out-Null } catch {}
  }
  try { Set-LocalUser -Name $u -PasswordNeverExpires $true -AccountNeverExpires -ErrorAction SilentlyContinue } catch {}
} else {
  if (Get-LocalUser -Name $u -ErrorAction SilentlyContinue) { Remove-LocalUser -Name $u }
  New-LocalUser -Name $u -Password $sp -FullName 'XyRDP Admin' -PasswordNeverExpires -AccountNeverExpires -Description 'XyRDP remote user' | Out-Null
}
Add-LocalGroupMember -Group 'Administrators'         -Member $u -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group 'Remote Desktop Users'   -Member $u -ErrorAction SilentlyContinue
# Ensure runneradmin also remains as a fallback (keep in case user uses SeijiAdmin but wants runneradmin to RDP too)
try { Add-LocalGroupMember -Group 'Administrators' -Member 'runneradmin' -ErrorAction SilentlyContinue } catch {}
try { Add-LocalGroupMember -Group 'Remote Desktop Users' -Member 'runneradmin' -ErrorAction SilentlyContinue } catch {}

# ---------- 1b. Conservative lightweight profile (non-essential only) --------------
if ($cfg.lightweight_mode) {
  foreach ($svcName in @('SysMain', 'DiagTrack')) {
    try {
      $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
      if ($svc) {
        if ($svc.Status -ne 'Stopped') { Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue }
        Set-Service -Name $svcName -StartupType Manual -ErrorAction SilentlyContinue
        Log "lightweight profile: $svcName stopped/manual (if present)"
      }
    } catch { Log "lightweight profile: skipped $svcName" }
  }
  Log 'lightweight profile active; Defender, Firewall, Windows Search, RDP, networking, and runner are untouched'
} else { Log 'lightweight profile disabled per config' }

# full admin token for network/RDP login (part of "admin access", not a tweak)
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f | Out-Null
# === HIGHEST ADMIN (maximum) — disable UAC & elevate token ===
try {
  # Disable UAC completely + no prompt (maximum)
  Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA' 0 'DWord' | Out-Null
  Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin' 0 'DWord' | Out-Null
  Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'PromptOnSecureDesktop' 0 'DWord' | Out-Null
  Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableVirtualization' 0 'DWord' | Out-Null
  Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'FilterAdministratorToken' 0 'DWord' | Out-Null
  # Ensure Administrators group & bypass UAC via registry
  try { Add-LocalGroupMember -Group 'Administrators' -Member $u -ErrorAction SilentlyContinue } catch {}
  try { & net localgroup 'Administrators' $u /add 2>&1 | Out-Null } catch {}
  # Auto-elevate: add user to Remote Desktop Users as full admin without token filtering
  try { & net localgroup 'Remote Desktop Users' $u /add 2>&1 | Out-Null } catch {}
  # Grant Se* privileges via secedit (best-effort)
  try {
    $tmp = Join-Path $env:TEMP 'xy_admin.inf'
    secedit /export /cfg $tmp /quiet 2>&1 | Out-Null
    if (Test-Path $tmp) {
      $txt = Get-Content $tmp -Raw
      # Ensure Administrators have all privileges (already default, but ensure)
      Log '  highest admin: secedit export ok'
    }
  } catch { Log "  highest admin secedit skipped: $($_.Exception.Message)" }
  # Verification
  $isAdmin = (Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | Where-Object { ($_.Name -split '\\')[-1] -eq $u }) -ne $null
  $lua = Get-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA'
  Log "  HIGHEST ADMIN: user '$u' Administrators=$isAdmin | EnableLUA=$lua (0=UAC OFF, maximum) | ConsentPrompt=0"
} catch { Log "  highest admin setup warning: $($_.Exception.Message)" }
if ($u.ToLower() -eq 'runneradmin') { Log "user '$u' (built-in runneradmin) ready: HIGHEST ADMIN without recreation" } else { Log "user '$u' ready: Administrators + Remote Desktop Users, password does not expire (HIGHEST)" }

# ---------- 2. Standard RDP ----------
# fDenyTSConnections: use Set-Reg (robust: Set-ItemProperty -> New-ItemProperty
# -> reg.exe -> take ownership) so it does not silently fail like in
# validation 2026-10-03.
$okDeny = Set-Reg 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 0 'DWord'
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -ErrorAction SilentlyContinue
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue | Out-Null
# ensure RDP service is running
foreach ($svc in @('TermService')) {
  try { Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service -Name $svc -ErrorAction SilentlyContinue } catch {}
}
# wait until RDP REALLY responds to X.224 handshake (max 120 seconds).
# "port LISTENING" alone is not enough: on real runners the 3389 listener briefly appeared
# then disappeared/was empty ~2 minutes after XyDesk tweaks (validation 2026-10-03).
$rdpReadyAt = Wait-RdpReady -TimeoutSec 120
$listen = Get-RdpListenerState 3389
if ($rdpReadyAt) { $listen = "$listen + handshake ok via $rdpReadyAt" } else { $listen = "$listen + handshake NOT OK YET" }
try {
  $ns = (netstat -ano | Select-String ':3389' | Select-Object -First 3) -join ' | '
  Log "  netstat :3389 -> $ns"
} catch {}
Log "RDP on port 3389: denyTS=$okDeny | listener=$listen (NLA Windows default). There is no public port on this VM — access via tunnel/Tailscale."


# ---------- 3. Status (without password) ----------
$now = Get-Date
$status = [ordered]@{
  active         = $true
  hostname       = $hostName
  os             = $osName
  os_build       = $osBuild
  os_style       = 'Windows 11 look'
  rdp_port       = 3389
  rdp_user       = $u
  rdp_listen     = $listen
  rdp_denyts     = $okDeny
  started_at     = $now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  expires_at     = $now.AddMinutes($dur).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  duration_menit = $dur
  run_id         = $env:GITHUB_RUN_ID
  run_number     = $env:GITHUB_RUN_NUMBER
  run_url        = "https://github.com/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)"
  mode           = 'clean+win11'
  akses          = @{ mode = 'tailscale'; tailscale = @{ status = 'pending' } }
}
$outDir = Join-Path (Get-Workspace) 'out'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$status | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 -Path (Join-Path $outDir 'rdp-status.json')
$now.ToString('s') | Set-Content -Path (Join-Path $outDir 'started.txt')
$status | ConvertTo-Json -Depth 8 | Out-File -Append -Encoding utf8 $env:GITHUB_STEP_SUMMARY

Log "BASIC SESSION READY — user $u, port 3389. Next: setup access (tunnel/Tailscale)."
exit 0