# ============================================================================
#  setup-extras.ps1 — EXTRA MODE (v2: Win11-style, without Tailscale/XyDesk)
# ----------------------------------------------------------------------------
#  Run AFTER setup-rdp.ps1 (+ setup-win11.ps1). All steps are
#  BEST-EFFORT: one failure won't kill the session.
#
#    1) read configuration from repo: assets/rdp-extras.json (edit from dashboard)
#    2) LIGHTSHOT   — automatic install (winget -> vendor installer), auto-run
#    3) TRANSLUCENT — TranslucentTB (portable -> winget) + transparency effects
#    4) WALLPAPER   — assets/wallpaper.* in repo (or WALLPAPER_URL)
#    5) VERIFICATION — RDP user ensured to be member of Administrators group
#    6) summarize results -> out/rdp-status.json (read by web dashboard)
#
#  Note: VM is disposable. Per-user settings are written to Default profile
#  (C:\Users\Default\NTUSER.DAT) so they activate automatically when RDP user logs in.
# ============================================================================

$XyTag = 'XyRDP:ekstra'
. "$PSScriptRoot/lib-common.ps1"

$u = if ($env:RDP_USER) { $env:RDP_USER } else { 'xyadmin' }

# ---------- 0. master switch ----------
$master = $true
if ($env:EXTRAS) {
  $e = $env:EXTRAS.Trim().ToLower()
  if (@('tidak', '0', 'false', 'no', 'off', 'skip', 'none') -contains $e) { $master = $false }
}
if (-not $master) {
  Log "EXTRAS='$env:EXTRAS' — all extra steps skipped."
  Update-Status @{ extras = @{ lightshot = 'skip'; translucent = 'skip'; wallpaper = 'skip'; wallpaper_file = ''; vscode = 'skip'; notepadpp = 'skip'; admin = $true } } | Out-Null
  exit 0
}

# ---------- 1. Configuration ----------
$cfg = Get-Cfg
if ($env:WALLPAPER_URL) { Log 'WALLPAPER_URL provided from workflow input — overrides file in repo' }
Log "lightshot=$($cfg.lightshot) | translucent=$($cfg.translucent) ($($cfg.translucent_mode)) | wallpaper=$($cfg.wallpaper) | win11_look=$($cfg.win11_look) | VSCode=$($cfg.vscode) | Notepad++=$($cfg.notepadpp)"

# Apply theme even if the user disabled the Win11 visual step.
$themeMode = if ($cfg.dark_theme) { 0 } else { 1 }
$transparencyMode = if ($cfg.translucent) { 1 } else { 0 }
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' $themeMode 'DWord' | Out-Null
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' $themeMode 'DWord' | Out-Null
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' $transparencyMode 'DWord' | Out-Null
Log "  theme $(if ($cfg.dark_theme) { 'dark' } else { 'light' }) + transparency=$($cfg.translucent) applied to Default profile"

# ---------- 2. LIGHTSHOT ----------
function Find-Lightshot {
  $cands = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Skillbrains\lightshot\Lightshot.exe'),
    (Join-Path $env:ProgramFiles            'Skillbrains\lightshot\Lightshot.exe')
  )
  foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
  foreach ($rk in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
    try {
      $e = Get-ItemProperty $rk -ErrorAction SilentlyContinue |
           Where-Object { $_.DisplayName -like '*Lightshot*' } | Select-Object -First 1
      if ($e -and $e.InstallLocation) {
        $p = Join-Path $e.InstallLocation 'Lightshot.exe'
        if (Test-Path $p) { return $p }
      }
    } catch {}
  }
  return $null
}

function Install-LightshotWinget {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Log '  winget not available'; return $false }
  try {
    $o = & winget install -e --id Skillbrains.Lightshot --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
    Log "  winget: $(Log-Tail $o 1)"
    Start-Sleep -Seconds 3
    if (Find-Lightshot) { Log '  winget succeeded (Lightshot found)'; return $true }
    Log '  winget finished but Lightshot not found, trying direct install...'
    return $false
  } catch { Log "  winget error: $($_.Exception.Message)"; return $false }
}

function Install-LightshotChoco {
  $choco = Get-Command choco.exe -ErrorAction SilentlyContinue
  if (-not $choco) { Log '  choco not available'; return $false }
  try {
    Log '  trying choco install lightshot...'
    $o = & $choco.Source install lightshot -y --no-progress 2>&1 | Out-String
    Log "  choco: $(Log-Tail $o 1)"
    Start-Sleep -Seconds 4
    if (Find-Lightshot) { Log '  choco succeeded'; return $true }
    return $false
  } catch { Log "  choco error: $($_.Exception.Message)"; return $false }
}

function Install-LightshotDirect {
  $exe = Join-Path $env:RUNNER_TEMP 'setup-lightshot.exe'
  try {
    Log '  downloading setup-lightshot.exe (app.prntscr.com)...'
    if (-not (Get-File 'https://app.prntscr.com/build/setup-lightshot.exe' $exe 180)) {
      Log '  download from prntscr failed, trying GitHub mirror...'
      if (-not (Get-File 'https://github.com/skillbrains/lightshot-installer/releases/latest/download/setup-lightshot.exe' $exe 180)) { Log '  all mirrors failed'; return $false }
    }
    if ((Get-Item $exe).Length -lt 500KB) { Log '  installer file too small, failed'; return $false }
    Start-Process -FilePath $exe -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-' -Wait
    Start-Sleep -Seconds 6
    return $true
  } catch { Log "  direct install failed: $($_.Exception.Message)"; return $false }
}

$resLightshot = 'skip'
if ($cfg.lightshot) {
  Log 'LIGHTSHOT: check / install (winget -> choco -> direct)...'
  $lsExe = Find-Lightshot
  if (-not $lsExe) { Install-LightshotWinget | Out-Null; $lsExe = Find-Lightshot }
  if (-not $lsExe) { Install-LightshotChoco | Out-Null; $lsExe = Find-Lightshot }
  if (-not $lsExe) { Install-LightshotDirect | Out-Null; $lsExe = Find-Lightshot }
  # final check: try registry lookup again
  if (-not $lsExe) { Start-Sleep -Seconds 2; $lsExe = Find-Lightshot }
  if ($lsExe) {
    Log "  installed: $lsExe"
    Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Run' 'Lightshot' $lsExe 'String' | Out-Null
    # ensure firewall allow
    try { New-NetFirewallRule -DisplayName 'Lightshot' -Direction Inbound -Program $lsExe -Action Allow -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Start-Process -FilePath $lsExe -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2; $proc=Get-Process -Name 'Lightshot' -ErrorAction SilentlyContinue; if($proc){Log '  Lightshot process running'} else {Log '  Lightshot installed but process not running yet (will auto-run at login)'} } catch {}
    # fix: Lightshot sometimes needs Visual C++ redist, installed in setup-samp, but check
    $resLightshot = 'ok'
  } else {
    Log '  FAILED to install Lightshot (non-critical, session continues) - check winget/choco logs'
    $resLightshot = 'failed'
  }
}

# ---------- 3. TRANSLUCENT (taskbar) ----------
function Find-TranslucentTB {
  $cands = @(
    'C:\Tools\TranslucentTB\TranslucentTB.exe',
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\TranslucentTB.exe'),
    (Join-Path $env:ProgramFiles 'TranslucentTB\TranslucentTB.exe')
  )
  foreach ($c in $cands) { if (Test-Path $c) { return $c } }
  try {
    $g = Get-ChildItem 'C:\Tools' -Recurse -Filter 'TranslucentTB.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g) { return $g.FullName }
  } catch {}
  return $null
}

function Install-TranslucentTBPortable {
  $dir = 'C:\Tools\TranslucentTB'
  $zip = Join-Path $env:RUNNER_TEMP 'ttb.zip'
  try {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Log '  downloading TranslucentTB portable (GitHub releases)...'
    $urls = @(
      'https://github.com/TranslucentTB/TranslucentTB/releases/latest/download/TranslucentTB-portable-x64.zip',
      'https://github.com/TranslucentTB/TranslucentTB/releases/download/2024.1/TranslucentTB-portable-x64.zip'
    )
    $ok=$false
    foreach($u in $urls){
      if(Get-File $u $zip 180){ if((Get-Item $zip).Length -gt 300KB){ $ok=$true; Log "  download succeeded from $u"; break } else { Log "  zip from $u too small"; Remove-Item $zip -Force -ErrorAction SilentlyContinue } }
    }
    if(-not $ok){ Log '  all mirrors failed'; return $false }
    # clean old
    if(Test-Path $dir){ Get-ChildItem $dir -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue }
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    # verify exe exists
    if(-not (Test-Path (Join-Path $dir 'TranslucentTB.exe'))){
      $found=Get-ChildItem $dir -Recurse -Filter 'TranslucentTB.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
      if($found){ Log "  found in $($found.DirectoryName)" }
    }
    return (Test-Path (Join-Path $dir 'TranslucentTB.exe')) -or (Find-TranslucentTB)
  } catch { Log "  portable failed: $($_.Exception.Message)"; return $false }
}

function Install-TranslucentTBWinget {
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    foreach ($id in @('TranslucentTB.TranslucentTB', 'CharlesMilette.TranslucentTB')) {
      try {
        $o = & winget install -e --id $id --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
        Log "  winget ($id): $(Log-Tail $o 1)"
        Start-Sleep -Seconds 3
        if (Find-TranslucentTB) { Log "  winget $id succeeded"; return $true }
      } catch { Log "  winget error ($id): $($_.Exception.Message)" }
    }
  }
  # fallback choco
  $choco = Get-Command choco.exe -ErrorAction SilentlyContinue
  if ($choco) {
    try {
      Log '  trying choco install translucenttb...'
      $o2 = & $choco.Source install translucenttb -y --no-progress 2>&1 | Out-String
      Log "  choco: $(Log-Tail $o2 1)"
      Start-Sleep -Seconds 3
      if (Find-TranslucentTB) { Log '  choco succeeded'; return $true }
    } catch { Log "  choco error: $($_.Exception.Message)" }
  }
  return $false
}

$resTrans = 'skip'
if ($cfg.translucent) {
  Log "TRANSLUCENT: taskbar mode '$($cfg.translucent_mode)'..."
  # native transparency effect (if setup-win11 skipped, this still applied)
  Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1 'DWord' | Out-Null

  $ttbExe = Find-TranslucentTB
  if (-not $ttbExe) { Install-TranslucentTBPortable | Out-Null; $ttbExe = Find-TranslucentTB }
  if (-not $ttbExe) { Install-TranslucentTBWinget | Out-Null; $ttbExe = Find-TranslucentTB }
  if ($ttbExe) {
    Log "  TranslucentTB: $ttbExe"
    $mode = $cfg.translucent_mode
    if (@('normal', 'opaque', 'clear', 'blur', 'acrylic', 'transparent') -notcontains $mode) { $mode = 'clear' }
    $ttbDir = Split-Path $ttbExe -Parent
    # always enable native transparency
    Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1 'DWord' | Out-Null
    try { Set-RegBoth 'Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 1 'DWord' | Out-Null } catch {}
    if ($ttbDir -like 'C:\Tools*') {
      $json = @{ desktop_appearance=@{accent=$mode;color="#00000000"};hide_tray=$false;disable_saving=$false;dynamic=@{enabled=$true} } | ConvertTo-Json -Depth 4
      try { Set-Content -Path (Join-Path $ttbDir 'settings.json') -Value $json -Encoding utf8 -ErrorAction Stop; Log "  settings.json -> mode=$mode (house translucent fix: EnableTransparency + AeroPeek)" }
      catch { Log "  settings.json failed to write: $($_.Exception.Message)" }
    } else { Log "  (MSIX/Store build — mode '$mode' configured via tray icon; native translucency remains active)" }
    Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Run' 'TranslucentTB' $ttbExe 'String' | Out-Null
    # ensure firewall allow & kill old instance then start
    try { Get-Process -Name 'TranslucentTB' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1 } catch {}
    try {
      Start-Process -FilePath $ttbExe -WorkingDirectory $ttbDir -ErrorAction SilentlyContinue; Start-Sleep -Seconds 4
      $proc=Get-Process -Name 'TranslucentTB' -ErrorAction SilentlyContinue
      if ($proc) { Log "  TranslucentTB process running (tray) PID $($proc.Id) - house translucent OK" }
      else { Log '  TranslucentTB process not visible yet (may require re-login, but taskbar is already transparent via registry)' }
    } catch { Log "  start TranslucentTB failed: $($_.Exception.Message)" }
    $resTrans = 'ok'
  } else {
    Log '  TranslucentTB failed to install — native transparency (registry) remains active as fallback'
    # fallback: ensure native transparency stays enabled
    Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1 'DWord' | Out-Null
    $resTrans = 'partial'
  }
}

# ---------- 3b. OPTIONAL CODING EDITORS -------------------------------------
# Git/Node/Python/7-Zip/Visual Studio already present on windows-2025 image.
# Only VS Code and Notepad++ are added if selected in the dashboard.
function Find-VSCode {
  foreach ($c in @(
    (Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe'),
    "${env:ProgramFiles(x86)}\Microsoft VS Code\Code.exe",
    (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe')
  )) { if ($c -and (Test-Path $c)) { return $c } }
  $cmd = Get-Command code.cmd -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}
function Find-NotepadPP {
  foreach ($c in @(
    (Join-Path $env:ProgramFiles 'Notepad++\notepad++.exe'),
    "${env:ProgramFiles(x86)}\Notepad++\notepad++.exe"
  )) { if ($c -and (Test-Path $c)) { return $c } }
  $cmd = Get-Command notepad++.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}
function Install-ChocoCodingTool([string]$Label, [string]$Package) {
  $choco = Get-Command choco.exe -ErrorAction SilentlyContinue
  if (-not $choco) { Log "  $Label skipped: Chocolatey not available"; return $false }
  try {
    Log "  installing $Label from Chocolatey ($Package)..."
    $out = & $choco.Source install $Package -y --no-progress 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($out) { Log "  Chocolatey $Label (exit $code): $(Log-Tail $out 2)" }
    return ($code -eq 0)
  } catch { Log "  installation of $Label failed: $($_.Exception.Message)"; return $false }
}

$resVSCode = 'skip'
if ($cfg.vscode) {
  Log 'VS CODE: check / install...'
  if (Find-VSCode) { $resVSCode = 'already present'; Log '  VS Code already available' }
  else {
    Install-ChocoCodingTool 'VS Code' 'vscode.install' | Out-Null
    Start-Sleep -Seconds 2
    $resVSCode = if (Find-VSCode) { 'ok' } else { 'failed' }
    Log "  VS Code: $resVSCode"
  }
}

$resNotepadPP = 'skip'
if ($cfg.notepadpp) {
  Log 'NOTEPAD++: check / install...'
  if (Find-NotepadPP) { $resNotepadPP = 'already present'; Log '  Notepad++ already available' }
  else {
    Install-ChocoCodingTool 'Notepad++' 'notepadplusplus.install' | Out-Null
    Start-Sleep -Seconds 2
    $resNotepadPP = if (Find-NotepadPP) { 'ok' } else { 'failed' }
    Log "  Notepad++: $resNotepadPP"
  }
}

# ---------- 4. WALLPAPER ----------
function Set-WallpaperLive([string]$imgPath) {
  try {
    Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class XyWall { [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni); }' -ErrorAction Stop
    [XyWall]::SystemParametersInfo(20, 0, $imgPath, 3) | Out-Null
    return $true
  } catch { Log "  set live wallpaper failed: $($_.Exception.Message)"; return $false }
}

$resWall = 'skip'; $wallName = ''
if ($cfg.wallpaper) {
  Log 'WALLPAPER: preparing image...'
  $wpDir = 'C:\XyRDP'
  $wpFile = $null; $srcUsed = ''

  # source order: workflow input -> file in repo (checkout) -> raw github
  if ($env:WALLPAPER_URL) {
    try {
      New-Item -ItemType Directory -Path $wpDir -Force | Out-Null
      $tmp = Join-Path $wpDir 'wp_download'
      if (Get-File $env:WALLPAPER_URL $tmp 180) {
        $ext = Get-ImageExt ([IO.File]::ReadAllBytes($tmp))
        if ($ext) { $wpFile = Join-Path $wpDir "wallpaper.$ext"; Move-Item $tmp $wpFile -Force; $srcUsed = 'WALLPAPER_URL' }
        else { Log '  URL is not a jpg/png/bmp image — ignored' }
      }
    } catch { Log "  download from WALLPAPER_URL failed: $($_.Exception.Message)" }
  }
  if (-not $wpFile) {
    $repoFile = $null
    foreach ($cand in @("$($cfg.wallpaper_file)", 'wallpaper.jpg', 'wallpaper.jpeg', 'wallpaper.png', 'wallpaper.bmp')) {
      $p = Join-Path (Get-Workspace) "assets\$cand"
      if (Test-Path $p) { $repoFile = $p; break }
    }
    if ($repoFile) {
      New-Item -ItemType Directory -Path $wpDir -Force | Out-Null
      $ext = [IO.Path]::GetExtension($repoFile).TrimStart('.').ToLower()
      $wpFile = Join-Path $wpDir "wallpaper.$ext"
      Copy-Item $repoFile $wpFile -Force
      $srcUsed = "repo ($(Split-Path $repoFile -Leaf))"
    }
  }
  if (-not $wpFile -and $env:GITHUB_REPOSITORY) {
    try {
      New-Item -ItemType Directory -Path $wpDir -Force | Out-Null
      $tmp = Join-Path $wpDir 'wp_raw'
      if (Get-File "https://raw.githubusercontent.com/$($env:GITHUB_REPOSITORY)/main/assets/$($cfg.wallpaper_file)" $tmp 120) {
        $ext = Get-ImageExt ([IO.File]::ReadAllBytes($tmp))
        if ($ext) { $wpFile = Join-Path $wpDir "wallpaper.$ext"; Move-Item $tmp $wpFile -Force; $srcUsed = 'raw github' }
      }
    } catch { Log "  raw github not present ($($_.Exception.Message))" }
  }

  if ($wpFile -and (Test-Path $wpFile)) {
    Log "  wallpaper: $wpFile (source: $srcUsed)"
    Set-RegBoth 'Control Panel\Desktop' 'Wallpaper'      $wpFile 'String' | Out-Null
    Set-RegBoth 'Control Panel\Desktop' 'WallpaperStyle' '10'     'String' | Out-Null
    Set-RegBoth 'Control Panel\Desktop' 'TileWallpaper'  '0'      'String' | Out-Null
    if (Set-WallpaperLive $wpFile) { Log '  wallpaper applied to live session' }
    $resWall = 'ok'; $wallName = Split-Path $wpFile -Leaf
  } else {
    Log '  no wallpaper (upload via dashboard or set WALLPAPER_URL)'
    $resWall = 'default'
  }
}

# ---------- 5. VERIFICATION: session must be ADMIN ----------
Log 'ACCESS VERIFICATION:'
$adminOk = $false
try {
  $grpExists = Get-LocalGroup -Name 'Administrators' -ErrorAction SilentlyContinue
  $usrExists = Get-LocalUser -Name $u -ErrorAction SilentlyContinue
  if ($grpExists -and $usrExists) {
    $members = Get-LocalGroupMember -Group 'Administrators' | ForEach-Object { ($_.Name -split '\\')[-1] }
    # Highest admin check: UAC
    $lua2 = Get-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA'
    $cpa = Get-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin'
    $rdpMembers = @()
    try { $rdpMembers = Get-LocalGroupMember -Group 'Remote Desktop Users' | ForEach-Object { ($_.Name -split '\\')[-1] } } catch {}
    $adminOk = ($members -contains $u)
    $adminTxt = $(if ($adminOk) { 'YES' } else { 'NO' })
    $rdpTxt   = $(if ($rdpMembers -contains $u) { 'YES' } else { 'NO' })
    Log ("  user '{0}' exists: YES | Administrators: {1} | Remote Desktop Users: {2} | HIGHEST ADMIN (UAC OFF): EnableLUA={3} Consent={4}" -f $u, $adminTxt, $rdpTxt, $lua2, $cpa)
    $lf = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'LocalAccountTokenFilterPolicy' -ErrorAction SilentlyContinue).LocalAccountTokenFilterPolicy
    Log "  LocalAccountTokenFilterPolicy = $lf (1 = full admin token for network/RDP sessions)"
  } else { Log '  user/group not found (should be created by setup-rdp.ps1)' }
} catch { Log "  verification failed: $($_.Exception.Message)" }

# ---------- 6. Summarize to status ----------
Update-Status @{ extras = [ordered]@{
    lightshot      = $resLightshot
    translucent    = $resTrans
    wallpaper      = $resWall
    wallpaper_file = $wallName
    vscode         = $resVSCode
    notepadpp      = $resNotepadPP
    admin          = $adminOk
} } | Out-Null
Close-DefaultHive

$adminTxt = $(if ($adminOk) { 'YES' } else { 'NO' })
Log ("DONE — lightshot={0} translucent={1} wallpaper={2} admin={3}" -f $resLightshot, $resTrans, $resWall, $adminTxt)
try { Probe-Rdp 'end step' | Out-Null } catch {}

exit 0