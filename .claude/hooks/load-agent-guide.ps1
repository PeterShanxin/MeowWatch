# SessionStart hook: inject docs/AGENT_GUIDE.md into the agent's context.
#
# Claude Code caps command-hook stdout (~10k chars), and the guide is larger
# (#104 review). A raw dump would truncate the tail — which is the Workflow
# section (release flow + versioning), the exact guidance agents keep missing.
# So we emit a PRIORITY-ORDERED, capped payload: the most-skipped operational
# sections first (Commands → Workflow → Architecture), then as much of the
# big Gotchas section as fits, truncated at a line boundary with a pointer to
# the full file on disk. Reordering only affects this injected digest; the
# file itself is unchanged.

$ErrorActionPreference = 'SilentlyContinue'

$root = git rev-parse --show-toplevel 2>$null
if (-not $root) { exit 0 }
$path = Join-Path $root 'docs/AGENT_GUIDE.md'
if (-not (Test-Path $path)) { exit 0 }

$raw = Get-Content -Raw $path
if (-not $raw) { exit 0 }

# Stay safely under the stdout cap, leaving headroom for the banner/footer.
$cap = 9000

# Small guides fit whole — emit verbatim.
if ($raw.Length -le $cap) { $raw; exit 0 }

# Split on level-2 headings and bucket by section.
$parts = [regex]::Split($raw, '(?=^## )', 'Multiline')
$header = ''
$byKey = @{}
foreach ($s in $parts) {
  $h = ($s -split "`n")[0]
  if ($h -like '# Agent Guide*')      { $header = $s }
  elseif ($h -like '## Commands*')     { $byKey['commands'] = $s }
  elseif ($h -like '## Workflow*')     { $byKey['workflow'] = $s }
  elseif ($h -like '## Architecture*') { $byKey['arch'] = $s }
  elseif ($h -like '## Gotchas*')      { $byKey['gotchas'] = $s }
  elseif ($h -like '## Maintaining*')  { $byKey['maint'] = $s }
}

# Most-skipped operational guidance first; bulky Gotchas last (cut if needed).
$order = @(
  $header,
  $byKey['commands'],
  $byKey['workflow'],
  $byKey['arch'],
  $byKey['gotchas'],
  $byKey['maint']
) | Where-Object { $_ }

$banner = "<!-- AGENT_GUIDE.md auto-loaded by SessionStart hook. Sections are reordered by priority and the tail may be truncated to fit the hook cap; the complete file is at docs/AGENT_GUIDE.md — open it for anything cut. -->`n`n"
$out = $banner + ($order -join '')

if ($out.Length -gt $cap) {
  $out = $out.Substring(0, $cap)
  $nl = $out.LastIndexOf("`n")
  if ($nl -gt 0) { $out = $out.Substring(0, $nl) }
  $out += "`n`n[...truncated to fit the hook output cap — open docs/AGENT_GUIDE.md for the rest of the Gotchas section and anything above that was cut.]"
}

$out
