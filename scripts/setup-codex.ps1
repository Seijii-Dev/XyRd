# setup-codex.ps1 - silent install of the real OpenAI Codex CLI (official npm package @openai/codex).
# Everything runs hidden/non-interactive. Sign-in (ChatGPT account) is the only manual step: run `codex` once.
$SeijiTag = 'SeijiPC:codex'
. "$PSScriptRoot/lib-common.ps1"
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$root   = 'C:\ProgramData\SeijiPC'
$prefix = Join-Path $root 'npm'          # shared prefix so every Windows user (incl. the RDP user) can run it
New-Item -ItemType Directory -Path $prefix -Force | Out-Null

function Refresh-Path {
  $m = [Environment]::GetEnvironmentVariable('Path','Machine'); $u = [Environment]::GetEnvironmentVariable('Path','User')
  $env:Path = (($m, $u) -join ';')
}
function Node-Major {
  try { $v = (& node --version 2>$null); if ($v -match '^v(\d+)') { return [int]$Matches[1] } } catch {}
  return 0
}
function Add-MachinePath([string]$dir) {
  $m = [Environment]::GetEnvironmentVariable('Path','Machine')
  if (($m -split ';') -notcontains $dir) {
    [Environment]::SetEnvironmentVariable('Path', ($m.TrimEnd(';') + ';' + $dir), 'Machine')
  }
  if (($env:Path -split ';') -notcontains $dir) { $env:Path = $env:Path.TrimEnd(';') + ';' + $dir }
}
function Test-Codex {
  Refresh-Path; Add-MachinePath $prefix
  $cmd = Join-Path $prefix 'codex.cmd'
  if (-not (Test-Path $cmd)) { return $null }
  try { $v = (& $cmd --version 2>&1 | Out-String).Trim(); if ($LASTEXITCODE -eq 0 -and $v -match '\d+\.\d+') { return $v } } catch {}
  return $null
}

$result = @{ codex = 'failed'; version = ''; node = ''; method = ''; shortcut = 'skip' }
try {
  Log 'CODEX: silent install of the official OpenAI Codex CLI (@openai/codex)...'
  Refresh-Path

  # 1) Node.js (Codex via npm needs a recent LTS)
  if ((Node-Major) -lt 22) {
    Log "  Node.js missing or too old (major=$(Node-Major)); installing Node LTS silently..."
    $installed = $false
    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
      & winget.exe install -e --id OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-Null
      Refresh-Path; $installed = (Node-Major) -ge 22
    }
    if (-not $installed -and (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
      & choco.exe install nodejs-lts -y --no-progress 2>&1 | Out-Null
      Refresh-Path; $installed = (Node-Major) -ge 22
    }
    if (-not $installed) { Log '  Node.js install did not reach v22+; will try the official PowerShell installer instead.' }
  }
  $result.node = (& node --version 2>$null)
  Log "  node=$($result.node)"

  # 2) Codex CLI via npm into the shared prefix
  if ((Node-Major) -ge 22 -and (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
    Log '  npm install -g @openai/codex --prefix ...'
    & npm.cmd install -g '@openai/codex@latest' --prefix $prefix --no-fund --no-audit --loglevel=error 2>&1 | Out-String | ForEach-Object { Log "  npm: $(Log-Tail $_ 2)" }
    $v = Test-Codex
    if (-not $v) {
      # Known Windows issue: main + platform package must match; pin both to the same version.
      Log '  codex did not start; pinning main + win32-x64 packages to the same version...'
      $ver = (& npm.cmd view '@openai/codex' version 2>$null | Out-String).Trim()
      if ($ver) {
        & npm.cmd install -g "@openai/codex@$ver" "@openai/codex-win32-x64@npm:@openai/codex@$ver-win32-x64" --prefix $prefix --no-fund --no-audit --loglevel=error 2>&1 | Out-Null
        $v = Test-Codex
      }
    }
    if ($v) { $result.method = 'npm'; $result.version = $v }
  }

  # 3) Fallback: official OpenAI PowerShell installer (silent)
  if (-not $result.version) {
    Log '  falling back to the official installer (chatgpt.com/codex/install.ps1)...'
    try {
      $tmp = Join-Path $env:TEMP 'codex-install.ps1'
      Invoke-WebRequest -UseBasicParsing -Uri 'https://chatgpt.com/codex/install.ps1' -OutFile $tmp
      & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $tmp 2>&1 | Out-Null
      Refresh-Path
      $c = Get-Command codex -ErrorAction SilentlyContinue
      if ($c) { $result.method = 'official-installer'; $result.version = (& codex --version 2>&1 | Out-String).Trim() }
    } catch { Log "  official installer error: $($_.Exception.Message)" }
  }

  if ($result.version) {
    $result.codex = 'ok'
    Log "CODEX: installed ($($result.method)) version $($result.version)"
    # Desktop shortcut for every user: opens PowerShell and starts codex (first run asks to sign in with ChatGPT)
    try {
      $desk = Join-Path $env:PUBLIC 'Desktop'; New-Item -ItemType Directory -Path $desk -Force | Out-Null
      $sh = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desk 'ChatGPT Codex.lnk'))
      $sh.TargetPath = 'powershell.exe'
      $sh.Arguments = '-NoLogo -NoExit -Command "Set-Location $HOME; codex"'
      $sh.WorkingDirectory = $env:PUBLIC
      $sh.Description = 'OpenAI Codex CLI - sign in with your ChatGPT account on first run'
      $sh.Save(); $result.shortcut = 'ok'
    } catch { $result.shortcut = 'failed'; Log "  shortcut failed: $($_.Exception.Message)" }
  } else {
    Log 'CODEX: installation failed (non-critical; session continues)'
  }
} catch {
  Log "CODEX: error: $($_.Exception.Message)"
}
Update-Status @{ codex = $result } | Out-Null
exit 0
