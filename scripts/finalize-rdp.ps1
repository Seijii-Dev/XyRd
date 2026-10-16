# SeijiPC: disconnect only its Tailscale session, never kill unrelated SSH processes.
$SeijiTag='SeijiPC:finalize'
. "$PSScriptRoot/lib-common.ps1"
$exe="$env:ProgramFiles\Tailscale\tailscale.exe"
if (Test-Path $exe) {
  try { & $exe down 2>$null | Out-Null; & $exe logout 2>$null | Out-Null } catch { Log 'Tailscale ownership of the tailnet needs to be checked' }
}
Log 'Session stopped. Self-hosted machine will not be removed automatically.'