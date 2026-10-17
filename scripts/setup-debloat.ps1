# ============================================================================
# setup-debloat.ps1 — remove Edge + Firefox (DEBLOAT=yes: visible first-login prompt, DEBLOAT=silent: automatic)
#
# When the configured RDP user logs in for the first time, Windows opens a
# visible PowerShell window and removes only Microsoft Edge and Mozilla Firefox.
# The scheduled task and temporary script delete themselves after completion.
# ============================================================================
$SeijiTag = 'SeijiPC:debloat'
. "$PSScriptRoot/lib-common.ps1"

$cfg = Get-Cfg
$rdpUser = if ($env:RDP_USER) { $env:RDP_USER.Trim() } elseif ($cfg.rdp_user) { [string]$cfg.rdp_user } else { 'SeijiAdmin' }
$taskName = 'SeijiPC-Debloat-FirstLogin'
$taskDir = Join-Path $env:ProgramData 'SeijiPC'
$firstLoginScript = Join-Path $taskDir 'debloat-first-login.ps1'

$firstLoginBody = @'
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$silentRun = ($env:SEIJI_DEBLOAT_SILENT -eq '1')
$taskName = 'SeijiPC-Debloat-FirstLogin'
$logPath = Join-Path $env:ProgramData 'SeijiPC\debloat-first-login.log'
New-Item -ItemType Directory -Path (Split-Path $logPath) -Force | Out-Null
function Say([string]$Message) {
  Write-Host $Message
  Add-Content -Path $logPath -Value ("[{0}] {1}" -f (Get-Date -Format s), $Message)
}
function Get-UninstallEntries {
  @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
  ) | ForEach-Object {
    Get-ItemProperty -Path $_ -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -and $_.UninstallString }
  }
}
function Remove-Firefox {
  Say ''
  Say 'Removing Mozilla Firefox...'
  $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
  if ($winget) {
    & $winget.Source uninstall --id Mozilla.Firefox --exact --silent --accept-source-agreements --disable-interactivity 2>&1 | ForEach-Object { Say "  $_" }
    if ($LASTEXITCODE -eq 0) { Say 'Mozilla Firefox removed with winget.'; return }
  }
  $entries = @(Get-UninstallEntries | Where-Object { $_.DisplayName -match '(?i)^Mozilla Firefox' })
  foreach ($entry in $entries) {
    try {
      $command = [string]$entry.UninstallString
      if ($command -match '^\s*"([^"]+)"\s*(.*)$') {
        $exe = $Matches[1]; $args = $Matches[2]
        if ($args -notmatch '(?i)(/S|/silent)') { $args += ' /S' }
        Start-Process -FilePath $exe -ArgumentList $args -Wait -WindowStyle Hidden
      } else {
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ($command + ' /S') -Wait -WindowStyle Hidden
      }
      Say "Firefox uninstall command completed: $($entry.DisplayName)"
    } catch { Say "Firefox uninstall failed: $($_.Exception.Message)" }
  }
  if (-not $entries) { Say 'Mozilla Firefox was not found.' }
}
function Remove-Edge {
  Say 'Microsoft Edge removal'
  Say 'Opening the Edge Installer folder and running:'
  Say 'cd "C:\Program Files (x86)\Microsoft\Edge\Application\*\Installer"'
  Say '.\setup.exe --uninstall --system-level --verbose-logging --force-uninstall'
  $installer = @(Get-ChildItem -Path 'C:\Program Files (x86)\Microsoft\Edge\Application\*\Installer\setup.exe' -File -ErrorAction SilentlyContinue)
  if (-not $installer) {
    $installer = @(Get-ChildItem -Path 'C:\Program Files\Microsoft\Edge\Application\*\Installer\setup.exe' -File -ErrorAction SilentlyContinue)
  }
  if (-not $installer) { Say 'Microsoft Edge setup.exe was not found.'; return }
  foreach ($setup in $installer | Sort-Object FullName -Descending | Select-Object -First 1) {
    try {
      Set-Location -LiteralPath $setup.DirectoryName
      Say "Running $($setup.FullName)"
      & $setup.FullName --uninstall --system-level --verbose-logging --force-uninstall 2>&1 | ForEach-Object { Say "  $_" }
      Say "Edge uninstall exit code: $LASTEXITCODE"
    } catch { Say "Edge uninstall failed: $($_.Exception.Message)" }
  }
}
try { $host.UI.RawUI.WindowTitle = 'Seiji-PC first-login debloat — Edge and Firefox' } catch {}
if (-not $silentRun) { Clear-Host }
Say 'Seiji-PC first-login debloat prompt'
Say 'This one-time prompt removes Microsoft Edge and Mozilla Firefox only.'
Say ''
Remove-Edge
Remove-Firefox
Say ''
Say 'Debloat complete. Only Edge and Firefox were targeted.'
if (-not $silentRun) { Say 'This window will close automatically in 8 seconds.'; Start-Sleep -Seconds 8 }
try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch {}
try { Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue } catch {}
'@

try {
  New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
  Set-Content -LiteralPath $firstLoginScript -Value $firstLoginBody -Encoding UTF8 -Force

  if ($env:DEBLOAT -eq 'silent') {
    # Silent mode: remove Edge and Firefox right now, hidden, before the first login.
    $env:SEIJI_DEBLOAT_SILENT = '1'
    Log 'Debloat silent mode: removing Microsoft Edge and Mozilla Firefox now (no window).'
    Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$firstLoginScript -Wait -WindowStyle Hidden
    $edgeLeft = Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    $ffLeft = (Test-Path "$env:ProgramFiles\Mozilla Firefox\firefox.exe") -or (Test-Path "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe")
    $edgeState = if ($edgeLeft) { 'present' } else { 'removed' }
    $ffState = if ($ffLeft) { 'present' } else { 'removed' }
    Log "Debloat result: edge=$edgeState firefox=$ffState"
    Update-Status @{ debloat = @{ mode = 'silent'; edge = $edgeState; firefox = $ffState } } | Out-Null
    exit 0
  }

  $userId = ".\$rdpUser"
  $actionArgs = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "' + $firstLoginScript + '"'
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $actionArgs
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
  $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Highest
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Description 'One-time visible Edge and Firefox removal on the first RDP login' -Force | Out-Null

  Log "Debloat first-login task registered for $userId. It will open a visible PowerShell prompt at the first RDP login."
  Update-Status @{ debloat = @{ mode = 'first-login-visible-prompt'; user = $rdpUser; edge = 'pending'; firefox = 'pending'; task = $taskName } } | Out-Null
} catch {
  Log "ERROR: could not register the first-login debloat task: $($_.Exception.Message)"
  Update-Status @{ debloat = @{ mode = 'registration-failed'; user = $rdpUser; error = $_.Exception.Message } } | Out-Null
  exit 1
}
exit 0
