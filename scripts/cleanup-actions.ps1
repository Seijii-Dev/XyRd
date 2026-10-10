# ============================================================================
#  cleanup-actions.ps1 — clean up Actions traces after a session ends:
#   1) delete OLD runs of this workflow (including their logs) to keep the repo tidy
#      and prevent old session IPs/logs from lingering. Keep KEEP_RUNS most recent runs.
#   2) requires a token with repo scope: use the CLEANUP_TOKEN secret (PAT), or
#      the Actions GITHUB_TOKEN (usually NOT sufficient — typically only has actions:read).
#
#  Env:
#    CLEANUP_TOKEN  — PAT with repo scope (recommended). Fallback: GITHUB_TOKEN.
#    KEEP_RUNS      — number of most recent runs to retain (default 3).
# ============================================================================
$ErrorActionPreference = 'Continue'
function Log([string]$m) { Write-Host "[XyRDP:cleanup] $m" }

$repo = $env:GITHUB_REPOSITORY
$wf   = $env:GH_WORKFLOW; if (-not $wf) { $wf = 'rdp-6h.yml' }
$keep = [int]($env:KEEP_RUNS -replace '\D',''); if ($keep -lt 1) { $keep = 3 }
$tok  = if ($env:CLEANUP_TOKEN) { $env:CLEANUP_TOKEN } else { $env:GITHUB_TOKEN }

if (-not $repo -or -not $tok) { Log 'repo/token unknown — skip'; exit 0 }

function GH([string]$method, [string]$apiPath) {
  $hdrs = @{ Authorization = "Bearer $tok"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'XyRDP'; 'X-GitHub-Api-Version' = '2022-11-28' }
  try { return Invoke-RestMethod -Uri "https://api.github.com$apiPath" -Method $method -Headers $hdrs -TimeoutSec 30 }
  catch { Log "GH $method $apiPath -> $($_.Exception.Message)"; return $null }
}

Log "cleaning up old runs (keeping $keep most recent)..."
try {
  $runs = GH 'GET' "/repos/$repo/actions/workflows/$wf/runs?per_page=100"
  $list = @($runs.workflow_runs)
  Log "  total runs seen: $($list.Count)"
  if ($list.Count -le $keep) { Log '  nothing to delete'; exit 0 }
  $old = $list | Select-Object -Skip $keep
  $n = 0
  $hdrs = @{ Authorization = "Bearer $tok"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'XyRDP'; 'X-GitHub-Api-Version' = '2022-11-28' }
  foreach ($r in $old) {
    # do not delete runs that are currently running (including self)
    if ($r.status -eq 'in_progress' -or $r.status -eq 'queued') { continue }
    try {
      Invoke-RestMethod -Method Delete -Uri "https://api.github.com/repos/$repo/actions/runs/$($r.id)" -Headers $hdrs -TimeoutSec 30 | Out-Null
      $n++
      Log "  run #$($r.run_number) ($($r.id)) deleted"
    } catch { Log "  delete run #$($r.run_number) failed: $($_.Exception.Message)" }
  }
  Log "  done: $n old runs deleted"
} catch { Log "cleanup failed (non-critical): $($_.Exception.Message)" }
exit 0