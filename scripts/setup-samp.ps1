$XyTag = 'XyRDP:samp'
. "$PSScriptRoot/lib-common.ps1"

$wantSamp = $true
if ($env:SAMP) {
  $e = $env:SAMP.Trim().ToLower()
  if (@('tidak','0','false','no','off','skip','none') -contains $e) { $wantSamp = $false }
}
$cfg = Get-Cfg
if ($cfg.PSObject.Properties['samp'] -and -not $cfg.samp) { $wantSamp = $false }

if (-not $wantSamp) {
  Log 'SAMP skipped (SAMP=tidak or samp=false in rdp-extras.json)'
  Update-Status @{ samp = @{ status='skip'; note='skipped per config' } } | Out-Null
  exit 0
}

Log '=== SETUP GTA SAMP — start ==='

# Choose the most free drive for the game
$gameRoot = 'C:\Games'
try {
  $d = Get-PSDrive -Name D -ErrorAction SilentlyContinue
  if ($d -and ($d.Free -gt 20GB)) {
    $gameRoot = 'D:\Games'
    Log "  Drive D: detected with free space ($([math]::Round($d.Free/1GB,1))GB free) -> using $gameRoot"
  } else {
    $cFree = (Get-PSDrive C).Free
    Log "  Using $gameRoot (C: free $([math]::Round($cFree/1GB,1))GB)"
  }
} catch {}
$gameDir = Join-Path $gameRoot 'GTA San Andreas'
$sampDir = $gameDir  # SA-MP installs into GTA dir
New-Item -ItemType Directory -Path $gameDir -Force | Out-Null

$gtaUrl = $null
if ($env:GTA_SA_URL) { $gtaUrl = $env:GTA_SA_URL.Trim() }
elseif ($env:GTA_SA_ZIP) { $gtaUrl = $env:GTA_SA_ZIP.Trim() }
elseif ($env:GTA_URL) { $gtaUrl = $env:GTA_URL.Trim() }
# also check generic workflow input WALLPAPER_URL not — do not use

$statusSamp = [ordered]@{
  status='pending'; game_dir=$gameDir; gta_installed=$false; samp_installed=$false
  gta_url_set=[bool]$gtaUrl; directx='pending'; vcredist='pending'; directplay='pending'
  samp_version=''; shortcut=''; note=''
}

# ---------- 1. Dependencies ----------
Log '  Dependencies: DirectPlay + VC++ + DirectX9 ...'

# DirectPlay (Windows feature for older games)
try {
  $dp = Enable-WindowsOptionalFeature -Online -FeatureName DirectPlay -All -NoRestart -ErrorAction SilentlyContinue
  if ($dp.RestartNeeded) { Log '  DirectPlay: enabled (restart needed but deferred ephemerally)' }
  $statusSamp.directplay = 'ok'
  Log '  DirectPlay: ok'
} catch { Log "  DirectPlay failed (non-critical): $($_.Exception.Message)"; $statusSamp.directplay='failed' }

# Visual C++ Redist 2013-2022 (required by SAMP & GTA)
function Install-VCRedist {
  $urls = @(
    'https://aka.ms/vs/17/release/vc_redist.x86.exe',
    'https://aka.ms/vs/17/release/vc_redist.x64.exe'
  )
  foreach ($u in $urls) {
    $out = Join-Path $env:RUNNER_TEMP ([IO.Path]::GetFileName($u))
    if ($u -like '*x86*') { $out = Join-Path $env:RUNNER_TEMP 'vc_redist.x86.exe' }
    else { $out = Join-Path $env:RUNNER_TEMP 'vc_redist.x64.exe' }
    try {
      if (Get-File $u $out 180) {
        Log "  VC++ $(Split-Path $out -Leaf): install..."
        $r = Start-Process -FilePath $out -ArgumentList '/install','/quiet','/norestart' -Wait -PassThru -ErrorAction SilentlyContinue
        Log "  VC++ $(Split-Path $out -Leaf): exit $($r.ExitCode)"
      }
    } catch { Log "  VC++ $u failed: $($_.Exception.Message)" }
  }
  # legacy 2013 for gta_sa.exe
  $v2013 = 'https://aka.ms/highdpimfc2013x86enu'
  # skip 2013 if fails — non-critical
}
try { Install-VCRedist; $statusSamp.vcredist='ok' } catch { $statusSamp.vcredist='failed' }

# DirectX End-User Runtime (June 2010) — small web installer (ANTI DxError)
# Runner already has DirectX12, Jun2010 is only for legacy D3DX9_xx.dll for GTA SA. If fails, WARP + d3d9on12 still works.
try {
  # check if d3dx9 already exists -> skip install to avoid DxError
  $hasD3dx = Test-Path 'C:\Windows\System32\d3dx9_43.dll'
  if ($hasD3dx) { Log '  DirectX9: d3dx9_43.dll already present -> skip Jun2010 (use built-in + WARP)'; $statusSamp.directx='ok (already present)' }
  else {
    $dx = Join-Path $env:RUNNER_TEMP 'dx_Jun2010.exe'
    if (Get-File 'https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe' $dx 300) {
      $dxDir = Join-Path $env:RUNNER_TEMP 'dx9'
      New-Item -ItemType Directory -Path $dxDir -Force | Out-Null
      # extract with log
      $ext = Start-Process -FilePath $dx -ArgumentList "/C","/T:$dxDir","/Q" -Wait -PassThru -ErrorAction SilentlyContinue
      Log "  DirectX extract exit $($ext.ExitCode) -> $dxDir"
      $setup = Join-Path $dxDir 'DXSETUP.exe'
      if (Test-Path $setup) {
        # silent with log to file, so DxError can be noticed but no popup
        $logDx = Join-Path $env:RUNNER_TEMP 'dxsetup.log'
        $proc = Start-Process -FilePath $setup -ArgumentList '/silent' -Wait -PassThru -ErrorAction SilentlyContinue
        $exit = $proc.ExitCode
        # read default DirectX log
        $dxLog = 'C:\Windows\Logs\DirectX.log'
        $tail = ''
        try { if (Test-Path $dxLog) { $tail = (Get-Content $dxLog -Tail 15 -ErrorAction SilentlyContinue) -join ' | ' } } catch {}
        if ($exit -eq 0 -or (Test-Path 'C:\Windows\System32\d3dx9_43.dll')) {
          Log "  DirectX9 runtime: installed (exit $exit) $tail"
          $statusSamp.directx='ok'
        } else {
          Log "  DirectX9 DXSETUP exit $exit (DxError?) -> fallback WARP. Log: $tail — skip non-fatal"
          $statusSamp.directx='skip (DxError fallback WARP)'
        }
      } else {
        Log "  DXSETUP.exe not found after extract — try dxwebsetup fallback"
        $dxweb = Join-Path $env:RUNNER_TEMP 'dxweb.exe'
        if (Get-File 'https://download.microsoft.com/download/1/7/1/1718CCC4-6315-4D8E-9543-8E28A4E18C4C/dxwebsetup.exe' $dxweb 180) {
          $pw = Start-Process -FilePath $dxweb -ArgumentList '/Q' -Wait -PassThru -ErrorAction SilentlyContinue
          Log "  DirectX web setup exit $($pw.ExitCode) (fallback)"
          $statusSamp.directx='ok (web fallback)'
        } else { $statusSamp.directx='skip (web failed)' }
      }
    } else { Log '  DirectX9 redist download failed — skip (WARP still present, GTA SA still runs in software)' ; $statusSamp.directx='skip' }
  }
} catch { Log "  DirectX failed (non-fatal, WARP backup): $($_.Exception.Message)"; $statusSamp.directx='skip (exception fallback WARP)' }

# .NET 3.5 for some asi loaders (optional)
try { Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart -ErrorAction SilentlyContinue | Out-Null; Log '  .NET 3.5 enabled' } catch {}

# Set high performance power plan for CPU
try { & powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null; Log '  Power plan: High performance' } catch {}

# ---------- 2. GTA SA Files ----------
$gtaInstalled = $false
if ($gtaUrl) {
  Log "  GTA_SA_URL provided — downloading GTA SA from your personal URL..."
  $zipPath = Join-Path $env:RUNNER_TEMP 'gta_sa.zip'
  # support Google Drive id extractor
  $realUrl = $gtaUrl
  $id = $null
  if ($gtaUrl -match 'drive\.google\.com.*[?&]id=([a-zA-Z0-9_-]+)') {
    $id = $Matches[1]
    $realUrl = "https://drive.google.com/uc?export=download&id=$id"
    Log "  Google Drive ID detected: $id -> $realUrl"
  } elseif ($gtaUrl -match 'drive\.google\.com/file/d/([a-zA-Z0-9_-]+)') {
    $id = $Matches[1]
    $realUrl = "https://drive.google.com/uc?export=download&id=$id"
    Log "  Google Drive file ID: $id"
  } elseif ($gtaUrl -match 'mediafire\.com/file/') {
    Log "  MediaFire detected — attempting direct download (may need page bypass)"; $realUrl = $gtaUrl
  } elseif ($gtaUrl -match 'dropbox\.com/') {
    $realUrl = $gtaUrl -replace '\?dl=0','?dl=1'
    Log "  Dropbox -> $realUrl"
  }
  Log "  Downloading... (may be 2-4GB, wait 5-15 minutes)"
  $ok = Get-File $realUrl $zipPath 1800  # 30 minute timeout
  if (-not $ok -and (Test-Path $zipPath) -and (Get-Item $zipPath).Length -lt 1MB) {
    # try gdrive direct with confirm token
    Log '  File small (<1MB) — maybe Google Drive confirmation page, trying bypass...'
    try {
      $html = Get-Content $zipPath -Raw -ErrorAction SilentlyContinue
      if ($html -match 'export=download[^"]*confirm=([a-zA-Z0-9_-]+)') {
        $tok = $Matches[1]
        $realUrl2 = "https://drive.google.com/uc?export=download&confirm=$tok&id=$id"
        Log "  Retry with confirm token: $tok"
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        $ok = Get-File $realUrl2 $zipPath 1800
      }
    } catch {}
  }
  if ($ok -and (Test-Path $zipPath)) {
    $sz = [math]::Round((Get-Item $zipPath).Length/1MB,1)
    Log "  Download complete: ${sz} MB -> extracting to $gameDir"
    # Detect 7z vs zip
    $seven = "$env:ProgramFiles\7-Zip\7z.exe"
    if (-not (Test-Path $seven)) { $seven = "${env:ProgramFiles(x86)}\7-Zip\7z.exe" }
    $extOk = $false
    try {
      if (Test-Path $seven) {
        & $seven x $zipPath "-o$gameRoot" -y 2>&1 | Out-Null
        $extOk = $true
      } else {
        Expand-Archive -Path $zipPath -DestinationPath $gameRoot -Force
        $extOk = $true
      }
    } catch { Log "  Extract failed: $($_.Exception.Message)" }
    if ($extOk) {
      # If zip contains "GTA San Andreas" folder, it's correct. If contains files directly, they're in gameRoot.
      # Check if gta_sa.exe exists in gameDir
      if (-not (Test-Path (Join-Path $gameDir 'gta_sa.exe'))) {
        # search for gta_sa.exe in gameRoot
        $found = Get-ChildItem $gameRoot -Recurse -Filter 'gta_sa.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
          $srcDir = Split-Path $found.FullName -Parent
          if ($srcDir -ne $gameDir) {
            Log "  GTA found in $srcDir -> moving to $gameDir"
            # move contents
            Get-ChildItem $srcDir -Force | ForEach-Object { Move-Item $_.FullName $gameDir -Force -ErrorAction SilentlyContinue }
          }
        }
      }
      if (Test-Path (Join-Path $gameDir 'gta_sa.exe')) {
        $gtaInstalled = $true
        Log '  GTA SA successfully extracted & gta_sa.exe found!'
      } else {
        Log '  Extraction finished but gta_sa.exe NOT found — check ZIP contents (must contain game files, not an installer folder)'
      }
    }
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
  } else {
    Log '  GTA SA download FAILED — file not downloaded. Check URL (must be direct download, not a preview page). Session continues; you can upload manually via RDP.'
  }
} else {
  Log '  GTA_SA_URL empty — skipping auto-download.'
  Log '  You can upload GTA SA manually after RDP connects: copy GTA folder to C:\Games\GTA San Andreas or D:\Games\GTA San Andreas via RDP drive / download via browser inside RDP.'
}

# Check if GTA already exists (from download or previous cache or manual)
if (Test-Path (Join-Path $gameDir 'gta_sa.exe')) { $gtaInstalled = $true }
# Also check C:\Games fallback
if (-not $gtaInstalled -and (Test-Path 'C:\Games\GTA San Andreas\gta_sa.exe')) {
  $gameDir = 'C:\Games\GTA San Andreas'
  $gtaInstalled = $true
  Log "  GTA found in fallback: $gameDir"
}
$statusSamp.gta_installed = $gtaInstalled

if (-not $gtaInstalled) {
  Log '  GTA SA not installed yet — SA-MP will still be installed; later place GTA files & click samp.exe'
  # create placeholder instructions on Desktop
  $desk = [Environment]::GetFolderPath('Desktop')
  if (-not $desk) { $desk = "C:\Users\$env:USERNAME\Desktop" }
  # also for Default user
  $readme = @"
HOW TO INSTALL GTA SA MANUALLY (because GTA_SA_URL empty / failed):

1. Inside RDP, open a browser (Edge/Chrome)
2. Download your own portable GTA SA (legal backup)
   - Can be from your Google Drive / Dropbox direct link
   - Or upload via RDP: from your PC, in mstsc -> Show Options -> Local Resources -> More -> Drives -> check C:
     then in RDP open \\tsclient\C and copy the GTA folder
3. Extract to: $gameDir
   Make sure gta_sa.exe is inside, not inside another subfolder
4. After that SA-MP (samp.exe) will be ready in the same folder — double-click to play

Storage saving tips:
- Delete installer / zip after extraction (can save 2-4GB)
- Full GTA SA ~3.5-4.7GB, SAMP ~15MB, so remaining storage 110GB is still plenty
"@
  try {
    New-Item -ItemType Directory -Path $gameDir -Force | Out-Null
    Set-Content -Path (Join-Path $gameDir 'HOW-TO-INSTALL-GTA.txt') -Value $readme -Encoding UTF8
    # copy to Default Desktop so RDP user sees it immediately
    $defDesk = 'C:\Users\Default\Desktop'
    New-Item -ItemType Directory -Path $defDesk -Force | Out-Null
    Copy-Item (Join-Path $gameDir 'HOW-TO-INSTALL-GTA.txt') (Join-Path $defDesk 'HOW-TO-INSTALL-GTA.txt') -Force -ErrorAction SilentlyContinue
    Log "  Manual instructions written to $gameDir\HOW-TO-INSTALL-GTA.txt"
  } catch {}
}

# ---------- 3. Install SA-MP Client ----------
$sampInstalled = $false
$sampVersion = ''
try {
  Log '  SA-MP client: downloading latest...'
  # No GitHub API for sa-mp, use stable direct URLs
  $sampUrls = @(
    'https://files.sa-mp.com/sa-mp-0.3.7-R5-1-MP-install.exe',
    'https://files.sa-mp.com/sa-mp-0.3.7-install.exe',
    'https://dracoblue.net/files/sa-mp-0.3.DL-R1-install.exe',
    'https://sa-mp.mp/downloads/sa-mp-0.3.7-R5-1-MP-install.exe',
    'https://gta-multiplayer.cz/downloads/sa-mp-0.3.7-R5-2-MP-install.exe',
    'https://libertycity.net/files/gta-san-andreas/183871-sa-mp-0.3.7-r5.html'
  )
  $sampExe = $null
  $dlOk = $false
  foreach ($u in $sampUrls) {
    $tmp = Join-Path $env:RUNNER_TEMP ("samp-install-" + [IO.Path]::GetFileName($u))
    Log "  Trying $u ..."
    if (Get-File $u $tmp 300) {
      if ((Get-Item $tmp).Length -gt 500KB) { $sampExe = $tmp; $dlOk = $true; $sampVersion = [IO.Path]::GetFileName($u); break }
      else { Log "  File too small ($((Get-Item $tmp).Length) bytes) -> skip" }
    }
  }
  if (-not $dlOk) {
    # fallback via site scrape (sa-mp.com + sa-mp.mp + gta-multiplayer.cz)
    foreach ($site in @('https://sa-mp.com/download.php','https://sa-mp.mp/downloads/','https://www.gta-multiplayer.cz/en/downloads/')) {
      Log "  Fallback scrape $site ..."
      try {
        $html = Invoke-WebRequest -Uri $site -UseBasicParsing -TimeoutSec 30 | Select-Object -ExpandProperty Content
        $m = [regex]::Match($html, 'href="([^"]*sa-mp[^"]*install\.exe)"')
        if ($m.Success) {
          $href = $m.Groups[1].Value
          if ($href -notlike 'http*') {
            $base = ($site -split '/')[0..2] -join '/'
            $href = "$base/$($href.TrimStart('/'))"
            if ($href -notlike 'http*') { $href = "https://sa-mp.com/$href" }
          }
          $tmp2 = Join-Path $env:RUNNER_TEMP 'samp-install-fallback.exe'
          if (Get-File $href $tmp2 300) { $sampExe = $tmp2; $dlOk = $true; $sampVersion = $href; Log "  Fallback obtained: $href"; break }
        }
      } catch { Log "  Scrape $site failed: $($_.Exception.Message)" }
    }
  }

  if ($dlOk -and $sampExe) {
    $sz = [math]::Round((Get-Item $sampExe).Length/1MB,2)
    Log "  SA-MP installer: $sampVersion (${sz} MB) -> $sampExe"

    # SA-MP installer is Inno Setup — can be silent with /SILENT or /VERYSILENT + /DIR=
    # We target $gameDir
    Log "  Installing SA-MP to $gameDir ..."
    $args = @("/SILENT", "/DIR=`"$gameDir`"", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-")
    # Installer expects gta_sa.exe present; if not, it will warn. We continue anyway.
    $proc = Start-Process -FilePath $sampExe -ArgumentList $args -Wait -PassThru -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    # Verification
    $checkFiles = @('samp.exe','samp.dll','samp.saa','SAMPUninstall.exe')
    $found = 0
    foreach ($f in $checkFiles) { if (Test-Path (Join-Path $gameDir $f)) { $found++ } }
    if ($found -ge 2) {
      $sampInstalled = $true
      Log "  SA-MP installed! ($found/$($checkFiles.Count) files found)"
    } else {
      Log "  SA-MP install exit $($proc.ExitCode) but files incomplete ($found/$($checkFiles.Count)) — trying manual extract with 7z"
      # fallback: extract with 7z (Inno Setup can be extracted)
      $seven = "$env:ProgramFiles\7-Zip\7z.exe"
      if (-not (Test-Path $seven)) { $seven = "${env:ProgramFiles(x86)}\7-Zip\7z.exe" }
      if (Test-Path $seven) {
        & $seven x $sampExe "-o$gameDir" -y 2>&1 | Out-Null
        if (Test-Path (Join-Path $gameDir 'samp.exe')) { $sampInstalled = $true; Log '  SA-MP extracted via 7z -> samp.exe present' }
      }
    }
    # Clean installer
    Remove-Item $sampExe -Force -ErrorAction SilentlyContinue
  } else {
    Log '  FAILED to download SA-MP installer from all mirrors — session continues, you can download manually inside RDP from sa-mp.com'
  }
} catch { Log "  SA-MP install error: $($_.Exception.Message)" }

$statusSamp.samp_installed = $sampInstalled
$statusSamp.samp_version = $sampVersion

# ---------- 4. Patch & Config ----------
if ($gtaInstalled -or $sampInstalled) {
  Log '  Configuring GTA & SAMP...'

  # Remove read-only gta_sa.set
  try {
    $setFile = Join-Path $gameDir 'gta_sa.set'
    if (Test-Path $setFile) { Set-ItemProperty $setFile -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue; Remove-Item $setFile -Force -ErrorAction SilentlyContinue; Log '  gta_sa.set removed (to allow fresh settings)' }
    $userFiles = Join-Path $gameDir 'User Files'
    if (Test-Path $userFiles) { Get-ChildItem $userFiles -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.IsReadOnly = $false } }
  } catch {}

  # Compatibility: Windows XP SP3 + run as admin + disable fullscreen optimizations
  function Set-Compat([string]$exePath) {
    if (-not (Test-Path $exePath)) { return }
    try {
      $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
      New-Item -Path $key -Force -ErrorAction SilentlyContinue | Out-Null
      Set-ItemProperty -Path $key -Name $exePath -Value '~ WINXPSP3 RUNASADMIN DISABLEDXMAXIMIZEDWINDOWEDMODE' -ErrorAction Stop
      Log "  Compat set: $(Split-Path $exePath -Leaf)"
    } catch { Log "  Compat failed for $exePath : $($_.Exception.Message)" }
    # also for Default user hive
    try {
      if (Open-DefaultHive) {
        $dk = "$($script:DefReg)\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
        # create Default key
        & reg add "HKU\XyRDP_Def\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers" /v "$exePath" /t REG_SZ /d "~ WINXPSP3 RUNASADMIN DISABLEDXMAXIMIZEDWINDOWEDMODE" /f 2>&1 | Out-Null
        Close-DefaultHive
      }
    } catch {}
  }
  Set-Compat (Join-Path $gameDir 'gta_sa.exe')
  Set-Compat (Join-Path $gameDir 'samp.exe')
  Set-Compat (Join-Path $gameDir 'gta-sa.exe')

  # Firewall allow
  foreach ($exe in @('gta_sa.exe','samp.exe')) {
    $p = Join-Path $gameDir $exe
    if (Test-Path $p) {
      try {
        New-NetFirewallRule -DisplayName "GTA $exe" -Direction Inbound -Program $p -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "GTA $exe OUT" -Direction Outbound -Program $p -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
      } catch {}
    }
  }

  # DirectX / graphics low tweak: create default gta_sa.set low via registry? SAMP uses file. We provide guidance.
  # silent patch & widescreen fix optional
  $wantExtra = $false
  if ($env:SAMP_EXTRA) { $e=$env:SAMP_EXTRA.Trim().ToLower(); if (@('ya','true','1','yes') -contains $e) { $wantExtra=$true } }
  if ($cfg.PSObject.Properties['samp_extra'] -and $cfg.samp_extra) { $wantExtra=$true }
  if ($wantExtra -and $gtaInstalled) {
    Log '  SAMP_EXTRA=yes — installing SilentPatch + Widescreen Fix (optional)...'
    # SilentPatch
    try {
      $spZip = Join-Path $env:RUNNER_TEMP 'silentpatch.zip'
      # URL from GitHub / mirrors — use stable mirror. If fails, skip.
      $spUrls = @(
        'https://github.com/CookiePLMonster/SilentPatch/releases/latest/download/SilentPatchSA.zip'
      )
      foreach ($u in $spUrls) {
        if (Get-File $u $spZip 180) {
          $seven = "$env:ProgramFiles\7-Zip\7z.exe"
          if (-not (Test-Path $seven)) { $seven = "${env:ProgramFiles(x86)}\7-Zip\7z.exe" }
          if (Test-Path $seven) { & $seven x $spZip "-o$gameDir" -y 2>&1 | Out-Null; Log '  SilentPatch installed' }
          break
        }
      }
    } catch { Log "  SilentPatch failed: $($_.Exception.Message)" }
    # Widescreen fix
    try {
      $wsZip = Join-Path $env:RUNNER_TEMP 'widescreen.zip'
      if (Get-File 'https://github.com/ThirteenAG/WidescreenFixesPack/releases/latest/download/GTASA.WidescreenFix.zip' $wsZip 180) {
        $seven = "$env:ProgramFiles\7-Zip\7z.exe"
        if (-not (Test-Path $seven)) { $seven = "${env:ProgramFiles(x86)}\7-Zip\7z.exe" }
        if (Test-Path $seven) {
          $tmpWs = Join-Path $env:RUNNER_TEMP 'ws_tmp'
          New-Item -ItemType Directory -Path $tmpWs -Force | Out-Null
          & $seven x $wsZip "-o$tmpWs" -y 2>&1 | Out-Null
          # copy d3d9.dll / widescreen files
          Get-ChildItem $tmpWs -Recurse -Filter '*.asi' -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName $gameDir -Force -ErrorAction SilentlyContinue }
          Get-ChildItem $tmpWs -Recurse -Filter '*.dll' -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName $gameDir -Force -ErrorAction SilentlyContinue }
          Log '  WidescreenFix attempted to install'
        }
      }
    } catch {}
  }

  # Remove read-only from game folder
  try { & attrib.exe -R "$gameDir\*.*" /S 2>&1 | Out-Null } catch {}

  # Desktop shortcut
  try {
    $desk = [Environment]::GetFolderPath('Desktop')
    if (-not $desk -or -not (Test-Path $desk)) { $desk = "C:\Users\$env:USERNAME\Desktop" }
    $defDesk = 'C:\Users\Default\Desktop'
    New-Item -ItemType Directory -Path $defDesk -Force | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    foreach ($targetDesk in @($desk, $defDesk)) {
      if (Test-Path (Join-Path $gameDir 'samp.exe')) {
        $lnk = $shell.CreateShortcut((Join-Path $targetDesk 'GTA SAMP.lnk'))
        $lnk.TargetPath = Join-Path $gameDir 'samp.exe'
        $lnk.WorkingDirectory = $gameDir
        $lnk.Description = 'GTA San Andreas Multiplayer'
        $lnk.Save()
      }
      if (Test-Path (Join-Path $gameDir 'gta_sa.exe')) {
        $lnk2 = $shell.CreateShortcut((Join-Path $targetDesk 'GTA San Andreas.lnk'))
        $lnk2.TargetPath = Join-Path $gameDir 'gta_sa.exe'
        $lnk2.WorkingDirectory = $gameDir
        $lnk2.Description = 'GTA San Andreas Single Player'
        $lnk2.Save()
      }
    }
    $statusSamp.shortcut = 'ok'
    Log '  Desktop Shortcuts: GTA SAMP + GTA SA created'
  } catch { Log "  Shortcut failed: $($_.Exception.Message)"; $statusSamp.shortcut='failed' }

  # Limit FPS & windowed hint
  try {
    $iniPath = Join-Path $gameDir 'samp.ini'
    # SAMP will create this on first run — we create defaults
    if (-not (Test-Path $iniPath)) {
      Set-Content -Path $iniPath -Value "fpslimit=60`r`nmulticore=1`r`n" -Encoding ASCII
    }
  } catch {}

  # Audio fix: ensure Windows Audio service is running (already in xydesk)
  try { Start-Service Audiosrv -ErrorAction SilentlyContinue } catch {}
}

# ---------- 5. Summary ----------
$freeAfter = -1
try { $freeAfter = [math]::Round((Get-PSDrive C).Free/1GB,1); $dFree2 = ""; try { $dFree2 = " D:$([math]::Round((Get-PSDrive D).Free/1GB,1))GB" } catch {}; Log "  Free space now: C:${freeAfter}GB${dFree2} (GTA ~4GB + SAMP 15MB)" } catch {}

if ($gtaInstalled -and $sampInstalled) { $statusSamp.status='installed_unverified'; $statusSamp.note='GTA SA and SA-MP files found. Test the launcher and server connection in the Windows session; gameplay success not yet verified.' }
elseif ($sampInstalled -and -not $gtaInstalled) { $statusSamp.status='partial'; $statusSamp.note='SA-MP installed but GTA SA missing — upload GTA to ' + $gameDir + ' then run samp.exe. See HOW-TO-INSTALL-GTA.txt on Desktop.' }
elseif ($gtaInstalled -and -not $sampInstalled) { $statusSamp.status='partial'; $statusSamp.note='GTA SA present but SA-MP failed to install — download manually from sa-mp.com inside RDP & install to the GTA folder.' }
else { $statusSamp.status='no-gta'; $statusSamp.note='GTA & SA-MP not installed (GTA_SA_URL empty & SAMP download failed). Follow instructions in HOW-TO-INSTALL-GTA.txt. Storage is sufficient.' }

# Add graphics info
try {
  $ad = @(Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name }) -join ' | '
  $statusSamp.gpu = $ad
} catch {}
$statusSamp.free_gb = $freeAfter
$statusSamp.game_dir = $gameDir

Update-Status @{ samp = $statusSamp } | Out-Null
$statusSamp | ConvertTo-Json -Depth 5 | Out-File -Append -Encoding utf8 $env:GITHUB_STEP_SUMMARY

Log "DONE — SAMP status=$($statusSamp.status) gta=$gtaInstalled samp=$sampInstalled dir=$gameDir"
exit 0