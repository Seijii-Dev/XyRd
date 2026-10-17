# setup-codex.ps1 - silent install of the real OpenAI Codex desktop app for Windows.
# Official package: Microsoft Store product 9PLM9XGG6VKS (package family OpenAI.Codex_*).
# NEVER install by name ("winget install Codex" resolves to an unrelated QR-reader app).
$SeijiTag = 'SeijiPC:codex-app'
. "$PSScriptRoot/lib-common.ps1"
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$StoreId = '9PLM9XGG6VKS'
$root    = 'C:\ProgramData\SeijiPC'
New-Item -ItemType Directory -Path $root -Force | Out-Null
$rdpUser = if ($env:RDP_USER) { $env:RDP_USER } else { 'SeijiAdmin' }
$result  = @{ codex_app = 'failed'; package = ''; version = ''; method = ''; shortcut = 'skip'; user_registration = 'skip' }

function Find-CodexPackage {
  foreach ($all in @($true, $false)) {
    try {
      $p = if ($all) { Get-AppxPackage -AllUsers -Name 'OpenAI.Codex*' -ErrorAction Stop } else { Get-AppxPackage -Name 'OpenAI.Codex*' -ErrorAction Stop }
      $p = @($p | Sort-Object Version -Descending | Select-Object -First 1)[0]
      if ($p) { return $p }
    } catch {}
  }
  return $null
}

function Invoke-WingetStoreInstall([int]$TimeoutSec = 600) {
  $w = Get-Command winget.exe -ErrorAction SilentlyContinue
  if (-not $w) {
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop } catch {}
    $w = Get-Command winget.exe -ErrorAction SilentlyContinue
  }
  if (-not $w) { Log '  winget is not available'; return $false }
  $out = Join-Path $env:TEMP 'codex-winget.log'
  $args = @('install','--id',$StoreId,'--source','msstore','--exact','--silent','--accept-source-agreements','--accept-package-agreements','--disable-interactivity')
  $proc = Start-Process -FilePath $w.Source -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError "$out.err"
  if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
    Log "  winget did not finish in ${TimeoutSec}s; stopping it (the Store may still be staging the package)."
    try { $proc.Kill() } catch {}
  } else { Log "  winget exit code: $($proc.ExitCode)" }
  try { Log "  winget: $(Log-Tail ((Get-Content $out -Raw -ErrorAction SilentlyContinue) + ' ' + (Get-Content "$out.err" -Raw -ErrorAction SilentlyContinue)) 3)" } catch {}
  # winget can return before the Store finishes registering the package: poll for it
  for ($i = 0; $i -lt 24; $i++) { if (Find-CodexPackage) { return $true }; Start-Sleep -Seconds 5 }
  return $false
}

try {
  Log "CODEX APP: silent install of the official OpenAI Codex app (Store id $StoreId)..."
  $pkg = Find-CodexPackage
  if ($pkg) {
    $result.method = 'already present'
    Log "  already installed: $($pkg.PackageFullName)"
  } else {
    foreach ($attempt in 1..2) {
      Log "  install attempt $attempt..."
      if (Invoke-WingetStoreInstall) { $result.method = 'winget-msstore'; break }
      Start-Sleep -Seconds 10
    }
    $pkg = Find-CodexPackage
  }

  if ($pkg) {
    $result.codex_app = 'ok'; $result.package = $pkg.PackageFamilyName; $result.version = [string]$pkg.Version
    Log "CODEX APP: installed $($pkg.PackageFullName)"

    # Application id from the package manifest -> AppUserModelID for shortcuts
    $appId = 'App'
    try {
      [xml]$m = Get-Content (Join-Path $pkg.InstallLocation 'AppxManifest.xml') -Raw
      $a = @($m.Package.Applications.Application)[0]; if ($a.Id) { $appId = $a.Id }
    } catch {}
    $aumid = "$($pkg.PackageFamilyName)!$appId"

    # Public Desktop shortcut (works for every user that has the package registered)
    try {
      $desk = Join-Path $env:PUBLIC 'Desktop'; New-Item -ItemType Directory -Path $desk -Force | Out-Null
      $sh = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desk 'Codex.lnk'))
      $sh.TargetPath = Join-Path $env:WINDIR 'explorer.exe'
      $sh.Arguments  = "shell:AppsFolder\$aumid"
      $sh.Description = 'OpenAI Codex app - sign in with your ChatGPT account on first run'
      $sh.Save(); $result.shortcut = 'ok'
    } catch { $result.shortcut = 'failed'; Log "  shortcut failed: $($_.Exception.Message)" }

    # Store apps are per-user: register the staged package for the RDP user at first logon (hidden, one-time)
    try {
      $reg = Join-Path $root 'Register-Codex.ps1'
      @"
`$pfn = '$($pkg.PackageFamilyName)'
`$have = Get-AppxPackage -Name 'OpenAI.Codex*' -ErrorAction SilentlyContinue
if (-not `$have) {
  try { Add-AppxPackage -RegisterByFamilyName -MainPackage `$pfn -ErrorAction Stop } catch {}
  `$have = Get-AppxPackage -Name 'OpenAI.Codex*' -ErrorAction SilentlyContinue
}
if (-not `$have -and (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
  & winget.exe install --id $StoreId --source msstore --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-Null
}
if (Get-AppxPackage -Name 'OpenAI.Codex*' -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName 'SeijiPC-Codex-Register' -Confirm:`$false -ErrorAction SilentlyContinue }
"@ | Set-Content $reg -Encoding UTF8
      $userId = ".\$rdpUser"
      $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$reg`""
      $trig   = New-ScheduledTaskTrigger -AtLogOn -User $userId
      $princ  = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
      Register-ScheduledTask -TaskName 'SeijiPC-Codex-Register' -Action $action -Trigger $trig -Principal $princ -Force | Out-Null
      $result.user_registration = 'task-registered'
      Log "  per-user registration task created for $userId"
    } catch { $result.user_registration = 'failed'; Log "  per-user registration failed: $($_.Exception.Message)" }
  } else {
    Log 'CODEX APP: installation failed (non-critical; session continues). Microsoft Store access is likely unavailable on this runner; a self-hosted Windows 11 runner is more reliable.'
  }
} catch {
  Log "CODEX APP: error: $($_.Exception.Message)"
}
Update-Status @{ codex = $result } | Out-Null
exit 0
