# ============================================================================
#  setup-xydesk.ps1 — HOST SETUP for XyDesk Remote (your Android APK)
# ----------------------------------------------------------------------------
#  This is the inline version of rdp.xydesk.my.id/host.ps1 (v0.5.34) + font
#  smoothing fixes from XyDesk-Remote commit v0.5.30, run directly from the repo
#  (does not fetch scripts from the internet).
#
#  What it does (idempotent, best-effort — all results reported as-is):
#    1) RDP: multi-session (fSingleSessionPerUser=0) + audio out & mic enabled
#    2) Graphics policy: AVC444 4:4:4 (preferred) + hardware encode + VGAdapter
#    3) Font smoothing: fNoFontSmoothing=0 + AllowFontAntiAlias=1 in
#       WinStations\RDP-Tcp  (this key is what Windows actually reads;
#       fAllowFontAntiAlias in Policy is no-op — finding from XyDesk-Remote v0.5.30)
#    4) Firewall: TCP/UDP 3389 + UDP 4433 (XyDesk QUIC audio bridge)
#    5) Services: ensure TermService + Audiosrv are running
#
#  IMPORTANT about access paths:
#    - XyDesk Remote -> "Full RDP Connection": fill Host + Port from the dashboard
#      (host = bore.pub / x.tcp.ngrok.io, port = the tunnel number). All RDP features
#      (AVC444, ClearType, rdpsnd audio, clipboard, keyboard) work over the TCP tunnel.
#    - XyDesk QUIC audio bridge (UDP 4433) CANNOT traverse a TCP tunnel — UDP port
#      is opened here so it's ready if the phone can reach UDP directly (LAN/tailnet).
#      Over the tunnel the client automatically falls back to RDP audio.
#    - The XyDesk client will probe QUIC 4433 then fail (expected) -> continue in RDP mode.
#
#  Configuration: assets/rdp-extras.json -> xydesk_host = true/false
# ============================================================================

$XyTag = 'XyRDP:xydesk'
. "$PSScriptRoot/lib-common.ps1"

$cfg = Get-Cfg
$skip = -not $cfg.xydesk_host
if ($env:XYDESK) {
  $e = $env:XYDESK.Trim().ToLower()
  if (@('tidak', 'no', '0', 'false', 'off', 'skip', 'none') -contains $e) { $skip = $true }
}
if ($skip) {
  Log 'XyDesk host setup skipped (input xydesk=no or xydesk_host=false in rdp-extras.json)'
  Update-Status @{ xydesk = @{ host = 'skip' } } | Out-Null
  exit 0
}

Log 'HOST SETUP XyDesk Remote (AVC444 + ClearType + multi-session + audio)...'
$tsRoot = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server'
$tsPol  = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
$tsTcp  = "$tsRoot\WinStations\RDP-Tcp"

# ---------- 0. Initial probe (RDP healthy?) ----------
$rdpAlive0 = Probe-Rdp 'before xydesk tweaks'

# ---------- 1. Multi-session: root key + POLICY key only ----------
# IMPORTANT (validation 2026-10-03): writing values to
#   HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp
# causes TermService to rebuild the RDP listener, and in the GitHub runner
# the 3389 listener did not recover (probe: initial=True -> reg=False, tunnel dead).
# So that key is now only READ (audit), not written.
$okDeny  = Set-Reg $tsRoot 'fDenyTSConnections'   0 'DWord'
$okMulti = Set-Reg $tsRoot 'fSingleSessionPerUser' 0 'DWord'
Set-Reg $tsPol 'fDenyTSConnections'   0 'DWord' | Out-Null
Set-Reg $tsPol 'fSingleSessionPerUser' 0 'DWord' | Out-Null
Log "  RDP: denyTS=$okDeny multisesion=$okMulti"
$rdpAlive1 = Probe-Rdp 'after multisession settings (root+policy)'

# ---------- 1b. Audio + font + wallpaper RDP: Policy (Policy overrides WinStations) ----------
# Audio: enable playback + mic via Policy (override WinStations without writing WinStations to avoid killing the listener)
$okAudioPol = Set-Reg $tsPol 'fDisableAudio' 0 'DWord'
$okMicPol   = Set-Reg $tsPol 'fDisableAudioCapture' 0 'DWord'
# RDP Wallpaper: do not block wallpaper during RDP (saves bandwidth -> black if off)
$okWallPol  = Set-Reg $tsPol 'fNoRemoteDesktopWallpaper' 0 'DWord'
# Audio Quality: 0=Dynamic, 2=High
Set-Reg $tsPol 'AudioQualityMode' 2 'DWord' | Out-Null
# Ensure Windows Audio services are running (Audiosrv + AudioEndpointBuilder)
try { Set-Service -Name 'AudioEndpointBuilder' -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service -Name 'AudioEndpointBuilder' -ErrorAction SilentlyContinue } catch {}
# Audit WinStations only for logging (do not write, so 3389 won't die)
$curAudio = Get-Reg $tsTcp 'fDisableAudio'
$curMic   = Get-Reg $tsTcp 'fDisableAudioCapture'
$curWall  = Get-Reg $tsTcp 'fNoRemoteDesktopWallpaper'
$curFs    = Get-Reg $tsTcp 'fNoFontSmoothing'
$curAa    = Get-Reg $tsTcp 'AllowFontAntiAlias'
$polAudio = Get-Reg $tsPol 'fDisableAudio'
$polMic   = Get-Reg $tsPol 'fDisableAudioCapture'
$polWall  = Get-Reg $tsPol 'fNoRemoteDesktopWallpaper'
Log "  policy: fDisableAudio=$polAudio fDisableAudioCapture=$polMic fNoRemoteDesktopWallpaper=$polWall (okAudioPol=$okAudioPol okMicPol=$okMicPol okWallPol=$okWallPol)"
Log "  audit WinStations\RDP-Tcp (no write): fDisableAudio=$curAudio fDisableAudioCapture=$curMic fNoRemoteDesktopWallpaper=$curWall fNoFontSmoothing=$curFs AllowFontAntiAlias=$curAa"
# Policy 0 = enabled, so check Policy first; WinStations is only fallback
$okAudio = ($polAudio -eq 0) -or (($null -eq $polAudio) -and ("$curAudio" -ne '1'))
$okMic   = ($polMic -eq 0) -or (($null -eq $polMic) -and ("$curMic" -ne '1'))
$okWall  = ($polWall -eq 0) -or (($null -eq $polWall) -and ("$curWall" -ne '1'))
$rdpAlive2 = Probe-Rdp 'after audio+wallpaper policy + WinStation audit'

# ---------- 2. XyDesk graphics policy (AVC444 / hardware encode) ----------
$okAvc  = Set-Reg $tsPol 'AVC444ModePreferred'       1 'DWord'
$okAvc2 = Set-Reg $tsPol 'AVCHardwareEncodePreferred' 1 'DWord'
Set-Reg $tsPol 'VGAdapter'            1 'DWord' | Out-Null
Set-Reg $tsPol 'bEnumerateHWBeforeSW' 1 'DWord' | Out-Null
Set-Reg $tsPol 'SelectTransport'      0 'DWord' | Out-Null
Set-Reg $tsPol 'fAllowDesktopComposition' 1 'DWord' | Out-Null
$avcTxt = if ($okAvc -and $okAvc2) { 'ok' } else { 'failed' }
Log "  graphics: AVC444ModePreferred+AVCHardwareEncodePreferred -> $avcTxt"
$rdpAlive3 = Probe-Rdp 'after graphics policy (AVC444)'

# ---------- 3. ClearType: via Default profile (per-user), not WinStation keys ----------
$fontTxt = 'failed'
if (Open-DefaultHive) {
  $dp = "$($script:DefReg)\Control Panel\Desktop"
  $f1 = Set-Reg $dp 'FontSmoothing'      '2' 'String'
  $f2 = Set-Reg $dp 'FontSmoothingType'   2  'DWord'
  Set-Reg $dp 'FontSmoothingGamma'      1400 'DWord' | Out-Null
  Set-Reg $dp 'FontSmoothingOrientation'  1  'DWord' | Out-Null
  Close-DefaultHive
  $fontTxt = if ($f1 -and $f2) { 'ok (ClearType Default profile)' } elseif ($f1 -or $f2) { 'partial' } else { 'failed' }
} else { $fontTxt = 'failed (Default profile could not be loaded)' }
Log "  ClearType: $fontTxt (FontSmoothing=2 + FontSmoothingType=2 in Default profile)"
$rdpAlive4 = Probe-Rdp 'after ClearType Default profile'

# ---------- 4. Firewall (opened in VM; from outside still only via tunnel) ----------
function Add-FwRule([string]$Name, [string]$Proto, [string]$Ports) {
  try {
    Remove-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName $Name -Direction Inbound -Action Allow `
      -Protocol $Proto -LocalPort $Ports -RemoteAddress '100.64.0.0/10' -Profile Any -ErrorAction Stop | Out-Null
    return $true
  } catch { Log "  firewall '$Name' failed: $($_.Exception.Message)"; return $false }
}
$fwTcp  = Add-FwRule 'XyDesk Remote RDP TCP'  'TCP' '3389'
$fwUdp  = Add-FwRule 'XyDesk Remote RDP UDP'  'UDP' '3389'
$fw4433 = Add-FwRule 'XyDesk Remote QUIC UDP' 'UDP' '4433'
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue | Out-Null
Log "  firewall: TCP3389=$fwTcp UDP3389=$fwUdp UDP4433=$fw4433"
$rdpAlive5 = Probe-Rdp 'after firewall rules'

# ---------- 5. Services ----------
$svcOk = @()
foreach ($svc in @('TermService', 'Audiosrv')) {
  try {
    Set-Service -Name $svc -StartupType Automatic -ErrorAction Stop
    Start-Service -Name $svc -ErrorAction Stop
    $svcOk += $svc
  } catch { Log "  service $svc failed: $($_.Exception.Message)" }
}
try { Start-Service -Name 'UmRdpService' -ErrorAction SilentlyContinue } catch {}
$svcTxt = if ($svcOk.Count -eq 2) { 'ok' } elseif ($svcOk.Count -eq 1) { "partial ($($svcOk[0]) running)" } else { 'failed' }
Log "  services: $svcTxt"
$rdpAlive6 = Probe-Rdp 'after starting services'

# ---------- 6. Private access ----------
Log 'Connect the phone and Windows to the same tailnet. RDP playback and audio capture use the RDP channel; the UDP bridge requires an additional host.'

# ---------- 6b. Verify RDP still alive after tweaks ----------
# IMPORTANT NOTE (validation 2026-10-03): after tweaks, the 3389 listener on
# this runner was down for ~2 minutes. We DO NOT restart TermService again (restart
# does not help and prolongs downtime) — we only measure and report the state
# so setup-access knows how long to wait.
$rdpReadyAt = Wait-RdpReady -TimeoutSec 150
if ($rdpReadyAt) { Log "  RDP still responsive after tweaks: $rdpReadyAt`:3389 (X.224 handshake OK)" }
else { Log '  WARNING: RDP did not respond to handshake after tweaks — setup-access will wait again' }

# ---------- 7. Status (as-is, not assumptions) ----------
$allOk = $okDeny -and $okMulti -and $okAudio -and $okMic -and $okWall -and $okAvc -and $okAvc2 -and ($fontTxt -like 'ok*')
Update-Status @{ xydesk = [ordered]@{
    host          = if ($allOk) { 'ok' } else { 'partial' }
    denyts        = if ($okDeny) { 'ok' } else { 'failed' }
    multisession  = if ($okMulti) { 'ok' } else { 'failed' }
    avc444        = $avcTxt
    fontsmoothing = $fontTxt
    audio_out     = if ($okAudio) { "ok (policy fDisableAudio=$polAudio, WinStations=$curAudio)" } else { "failed (policy=$polAudio WinStations=$curAudio)" }
    audio_mic     = if ($okMic) { "ok (policy fDisableAudioCapture=$polMic, WinStations=$curMic) - phone mic redirect enabled, Allow on phone" } else { "failed (policy=$polMic WinStations=$curMic)" }
    wallpaper_rdp = if ($okWall) { "ok (policy fNoRemoteDesktopWallpaper=$polWall) - RDP wallpaper shown, check client Experience→Wallpaper ON" } else { "failed (policy=$polWall WinStations=$curWall) - RDP wallpaper blocked" }
    firewall      = "tcp3389=$fwTcp udp3389=$fwUdp udp4433=$fw4433"
    services      = $svcTxt
    rdp_ready     = if ($rdpReadyAt) { "$rdpReadyAt (handshake OK)" } else { 'not yet' }
    rdp_probe     = "initial=$rdpAlive0 multi=$rdpAlive1 audio=$rdpAlive2 graphics=$rdpAlive3 clear=$rdpAlive4 fw=$rdpAlive5 svc=$rdpAlive6"
    quic_udp4433  = 'opened in VM (not via TCP tunnel)'
    akses         = if ($addr) { $addr } else { '(pending)' }
    note          = if ($allOk) { 'Host ready for XyDesk Remote clients in Full RDP Connection mode (Host+Port tunnel). WinStations\RDP-Tcp keys are intentionally NOT written so the 3389 listener does not die in the GitHub runner.' }
                    else { 'Some host settings failed — sessions still work over normal RDP; check Host setup XyDesk log steps' }
} } | Out-Null

if ($allOk) {
  Log 'DONE — XyDesk host ready: AVC444 + ClearType + multi-session + audio/mic'
} else {
  Log "DONE (partial) — check lines with 'failed' above; sessions are still usable over normal RDP"
}
exit 0