# ============================================================================
#  setup-win11.ps1 — "Windows 11 look" for the windows-2025 runner
# ----------------------------------------------------------------------------
#  GitHub-hosted windows-2025 is the Windows 11-based hosted runner target.
#  This script applies Windows 11 shell and personalization settings. For a
#  pinned physical/VM Windows 11 machine, use the self-hosted runner option:
#
#    1) Server Manager does not appear at login, IE Enhanced Security off
#    2) Shutdown Event Tracker off (won't ask "reason for shutdown")
#    3) Personalization: transparency, centered taskbar, search icon, dark theme
#    4) Wallpaper + login/lock screen background in Windows 11 style
#    5) Ctrl+Alt+Del not required on the sign-in screen (like Windows 11)
#    6) Windows Search enabled so the Start menu can search
#    7) OS identity is never spoofed; the actual OS is reported unchanged
#
#  All steps are BEST-EFFORT: failure of one does not abort the session.
#  Configuration: assets/rdp-extras.json -> win11_look / win11_badge /
#  win11_wallpaper (can be changed from the web dashboard).
# ============================================================================

$XyTag = 'XyRDP:win11'
. "$PSScriptRoot/lib-common.ps1"

# ---------- 0. master switch ----------
$skip = $false
if ($env:WIN11) { $e = $env:WIN11.Trim().ToLower(); if (@('tidak', 'no', '0', 'false', 'off', 'skip', 'none') -contains $e) { $skip = $true } }
$cfg = Get-Cfg
if (-not $cfg.win11_look) { $skip = $true }
if ($skip) {
  Log 'Windows 11 tweak skipped (input WIN11=no or win11_look=false in rdp-extras.json)'
  Update-Status @{ win11 = @{ look = 'skip' } } | Out-Null
  exit 0
}
Log "starting Windows 11 tweak (badge=$($cfg.win11_badge) wallpaper=$($cfg.win11_wallpaper) dark=$($cfg.dark_theme) lightweight=$($cfg.lightweight_mode))"

$os = try { Get-CimInstance Win32_OperatingSystem } catch { $null }
Log "  Installed OS: $($os.Caption) build $($os.Version) — applying Windows 11-style settings only"

# ---------- 1. remove "Server" characteristics ----------
Open-DefaultHive | Out-Null

# Server Manager: don't open automatically at logon
Set-RegBoth 'Software\Microsoft\ServerManager' 'DoNotOpenServerManagerAtLogon' 1 'DWord' | Out-Null
# Shutdown Event Tracker: don't ask for a reason
Set-Reg 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Reliability\Shutdown' 'ShutdownReasonOn' 0 'DWord' | Out-Null
# IE Enhanced Security Configuration (2 keys: admin + user)
foreach ($guid in @('{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}', '{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}')) {
  Set-Reg "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Active Setup\Installed Components\$guid" 'IsInstalled' 0 'DWord' | Out-Null
}
Log '  Server Manager & Shutdown Event Tracker disabled, IE ESC turned off'

# ---------- 2. Windows 11 style sign-in screen ----------
# Windows 11 does not require Ctrl+Alt+Del on the sign-in screen
Set-Reg 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' 'DisableCAD' 1 'DWord' | Out-Null
# hide version/edition text in the desktop corner
Set-RegBoth 'Control Panel\Desktop' 'PaintDesktopVersion' 0 'DWord' | Out-Null
# hide the built-in Administrator account so the sign-in screen is clean (job runner
# runs as runneradmin, so it is unaffected)
try { Disable-LocalUser -Name 'Administrator' -ErrorAction Stop; Log '  built-in Administrator account disabled (clean sign-in screen)' } catch { Log "  disabling Administrator skipped: $($_.Exception.Message)" }

# ---------- 3. Windows 11 style personalization ----------
$themeMode = if ($cfg.dark_theme) { 0 } else { 1 }
$transparencyMode = if ($cfg.translucent) { 1 } else { 0 }
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' $transparencyMode 'DWord' | Out-Null
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'ColorPrevalence'   1 'DWord' | Out-Null   # accent color on taskbar (Win11-like)
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' $themeMode 'DWord' | Out-Null
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme'   $themeMode 'DWord' | Out-Null
# taskbar: never combine buttons (Win11 default), search box, Task View button
$adv = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-RegBoth $adv 'TaskbarAl'             1 'DWord' | Out-Null
Set-RegBoth $adv 'TaskbarGlomLevel'      0 'DWord' | Out-Null
Set-RegBoth $adv 'TaskbarSmallIcons'     0 'DWord' | Out-Null
Set-RegBoth $adv 'SearchboxTaskbarMode'  1 'DWord' | Out-Null
Set-RegBoth $adv 'ShowTaskViewButton'    1 'DWord' | Out-Null
Set-RegBoth $adv 'EnableAutoTray'        0 'DWord' | Out-Null
# Windows 11 blue accent color (#0078D7)
$dwm = 'Software\Microsoft\Windows\DWM'
Set-RegBoth $dwm 'ColorPrevalence'     1 'DWord'  | Out-Null
Set-RegBoth $dwm 'AccentColor'         0xffd77800 'DWord' | Out-Null   # ABGR
Set-RegBoth $dwm 'ColorizationColor'   0xc40078d7 'DWord' | Out-Null
Set-RegBoth $dwm 'ColorizationAfterglow' 0xc40078d7 'DWord' | Out-Null
Set-RegBoth $dwm 'EnableWindowColorization' 1 'DWord' | Out-Null
Log "  personalization applied (theme=$(if ($cfg.dark_theme) { 'dark' } else { 'light' }), transparency=$($cfg.translucent), accent, taskbar)"

# ---------- 4. enable Windows Search (Start menu can search) ----------
try {
  Set-Service -Name WSearch -StartupType Automatic -ErrorAction Stop
  Start-Service -Name WSearch -ErrorAction Stop
  Log '  Windows Search service: enabled (Start menu can search apps)'
  $searchStatus = 'ok'
} catch { Log "  Windows Search could not be enabled (non-critical): $($_.Exception.Message)"; $searchStatus = 'failed' }

# ---------- 5. wallpaper & sign-in background ----------
function Get-Win11WallpaperFile {
  $names = @()
  # Dashboard/current config choices should be preferred; wallpaper-win11.* is only
  # a fallback. Otherwise, the built-in image could override an uploaded wallpaper.
  if ($cfg.wallpaper_file) { $names += @($cfg.wallpaper_file) }
  if ($cfg.win11_wallpaper) { $names += @('wallpaper-win11.jpg', 'wallpaper-win11.png') }
  $names += @('wallpaper.jpg', 'wallpaper.jpeg', 'wallpaper.png', 'wallpaper.bmp')
  foreach ($n in $names) {
    $p = Join-Path (Get-Workspace) "assets\$n"
    if (Test-Path $p) { return $p }
  }
  if ($env:GITHUB_REPOSITORY -and $cfg.wallpaper_file) {
    $tmp = Join-Path $env:RUNNER_TEMP 'wp-win11.jpg'
    $rawName = [IO.Path]::GetFileName($cfg.wallpaper_file)
    if (Get-File "https://raw.githubusercontent.com/$($env:GITHUB_REPOSITORY)/main/assets/$rawName" $tmp 120) { return $tmp }
  }
  return $null
}

# Resize + compress to JPEG < 256 KB (Windows sign-in background limit)
function Save-LogonBackground([string]$Src, [string]$Dst, [int]$MaxKB = 240) {
  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $img = [System.Drawing.Image]::FromFile($Src)
    $w = 1920; $h = [int]($img.Height * (1920.0 / $img.Width)); if ($h -gt 1080) { $h = 1080; $w = [int]($img.Width * (1080.0 / $img.Height)) }
    foreach ($q in @(85, 75, 65, 55)) {
      $bmp = New-Object System.Drawing.Bitmap($w, $h)
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.DrawImage($img, 0, 0, $w, $h); $g.Dispose()
      $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
      $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
      $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [int64]$q)
      $bmp.Save($Dst, $enc, $ep)
      $bmp.Dispose()
      $kb = [math]::Round((Get-Item $Dst).Length / 1KB)
      if ($kb -le $MaxKB) { Log "  sign-in background: ${w}x${h}, ${kb} KB (quality $q)"; $img.Dispose(); return $true }
    }
    $img.Dispose()
    Log "  sign-in background: $([math]::Round((Get-Item $Dst).Length / 1KB)) KB (over 256 KB limit, Windows may ignore)"
    return $true
  } catch { Log "  failed to prepare sign-in background: $($_.Exception.Message)"; return $false }
}

$wallStatus = 'skip'
$wpFile = Get-Win11WallpaperFile
if ($wpFile) {
  try {
    New-Item -ItemType Directory -Path 'C:\XyRDP' -Force | Out-Null
    $ext = [IO.Path]::GetExtension($wpFile).TrimStart('.').ToLower(); if (-not $ext) { $ext = 'jpg' }
    $local = "C:\XyRDP\wallpaper-win11.$ext"
    Copy-Item $wpFile $local -Force
    # desktop wallpaper (Default profile + current session)
    Set-RegBoth 'Control Panel\Desktop' 'Wallpaper'      $local 'String' | Out-Null
    Set-RegBoth 'Control Panel\Desktop' 'WallpaperStyle' '10'    'String' | Out-Null   # 10 = Fill
    Set-RegBoth 'Control Panel\Desktop' 'TileWallpaper'  '0'     'String' | Out-Null
    try {
      Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class XyWall { [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni); }' -ErrorAction Stop
      [XyWall]::SystemParametersInfo(20, 0, $local, 3) | Out-Null
    } catch {}
    # sign-in / lock screen
    $oobe = 'C:\Windows\System32\oobe\info\backgrounds'
    New-Item -ItemType Directory -Path $oobe -Force | Out-Null
    Save-LogonBackground $local (Join-Path $oobe 'backgroundDefault.jpg') | Out-Null
    Set-Reg 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\Background' 'OEMBackground' 1 'DWord' | Out-Null
    $wallStatus = 'ok'
    Log "  wallpaper applied: $local (+ sign-in background)"
  } catch { Log "  wallpaper failed: $($_.Exception.Message)"; $wallStatus = 'failed' }
} else {
  Log '  no wallpaper file in assets/ — using default wallpaper'
  $wallStatus = 'default'
}

# ---------- 6. OS identity ----------------------------------------------------
# Never rewrite ProductName, EditionID, or ProductType to impersonate Windows 11.
# The status reports the real operating system returned by Win32_OperatingSystem.
$badgeStatus = 'not_modified'
Log '  OS identity unchanged; Windows 11-style mode does not spoof the installed edition'
Close-DefaultHive

# ---------- 7. summarize to status ----------
Update-Status @{ win11 = [ordered]@{
    look = 'ok'; badge = $badgeStatus; wallpaper = $wallStatus; search = $searchStatus
    os = if ($os) { $os.Caption } else { 'Windows' }
    note = 'Windows 11-style appearance only; use a Windows 11 self-hosted runner for the actual OS'
} } | Out-Null

Log "DONE — win11 look=ok badge=$badgeStatus wallpaper=$wallStatus search=$searchStatus"
try { Probe-Rdp 'end step' | Out-Null } catch {}

exit 0