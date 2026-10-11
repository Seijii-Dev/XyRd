# ============================================================================
# setup-debloat.ps1 — remove only Microsoft Edge and Mozilla Firefox
#
# This script is intentionally narrow. It does not remove OneDrive, Xbox,
# arbitrary AppX packages, Windows components, or other installed software.
# ============================================================================
$XyTag = 'XyRDP:debloat'
. "$PSScriptRoot/lib-common.ps1"

function Invoke-WingetUninstall([string]$Id, [string]$Label) {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Log "  winget is not available; will try the uninstall registry fallback for $Label"
    return $false
  }
  try {
    $output = & winget uninstall --id $Id --exact --silent --accept-source-agreements --disable-interactivity 2>&1 | Out-String
    Log "  $Label (winget): $(Log-Tail $output 3)"
    return ($LASTEXITCODE -eq 0)
  } catch {
    Log "  $Label (winget) failed: $($_.Exception.Message)"
    return $false
  }
}

function Get-UninstallEntries {
  $paths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  foreach ($path in $paths) {
    Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -and $_.UninstallString }
  }
}

function Invoke-RegistryUninstall([string]$NamePattern, [string]$Label) {
  $entries = @(Get-UninstallEntries | Where-Object { $_.DisplayName -match $NamePattern })
  if (-not $entries) {
    Log "  $Label: no registry uninstall entry found"
    return $false
  }
  $removed = $false
  foreach ($entry in $entries) {
    try {
      $command = [string]$entry.UninstallString
      if ($command -match '(?i)msiexec(?:\.exe)?') {
        $command = $command -replace '(?i)\s/I\s', ' /X '
        if ($command -notmatch '(?i)\s/q') { $command += ' /qn' }
        if ($command -notmatch '(?i)norestart') { $command += ' /norestart' }
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $command -Wait -WindowStyle Hidden
      } elseif ($command -match '^\s*"([^"]+)"\s*(.*)$') {
        $exe = $Matches[1]; $args = $Matches[2]
        if ($Label -eq 'Mozilla Firefox' -and $args -notmatch '(?i)(/S|/silent)') { $args += ' /S' }
        Start-Process -FilePath $exe -ArgumentList $args -Wait -WindowStyle Hidden
      } else {
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $command -Wait -WindowStyle Hidden
      }
      Log "  $Label (registry): uninstall command completed for $($entry.DisplayName)"
      $removed = $true
    } catch {
      Log "  $Label (registry) failed: $($_.Exception.Message)"
    }
  }
  return $removed
}

Log 'Debloat scope: Microsoft Edge and Mozilla Firefox only.'
$edgeRemoved = Invoke-WingetUninstall 'Microsoft.Edge' 'Microsoft Edge'
if (-not $edgeRemoved) { $edgeRemoved = Invoke-RegistryUninstall '^Microsoft Edge$' 'Microsoft Edge' }

$firefoxRemoved = Invoke-WingetUninstall 'Mozilla.Firefox' 'Mozilla Firefox'
if (-not $firefoxRemoved) { $firefoxRemoved = Invoke-RegistryUninstall '^Mozilla Firefox' 'Mozilla Firefox' }

Log "Debloat complete: Edge removed=$edgeRemoved | Firefox removed=$firefoxRemoved"
Log 'No OneDrive, Xbox, AppX, or other Windows components were targeted.'
exit 0
