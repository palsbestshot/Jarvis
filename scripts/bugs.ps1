# scripts/bugs.ps1 -- Jarvis bug workflow helper.
#
# Pallav reports bugs via the Jarvis chat: "bug: draft button spins forever".
# The report_bug tool writes them to Firestore users/pallav/bugs/*.
#
# This script is for Claude Code sessions on the PC to pick them up:
#   .\scripts\bugs.ps1 list
#     -> prints open bugs (status == 'new' or 'in_progress') as plain text
#       ready to paste into the conversation
#   .\scripts\bugs.ps1 fix <bugId> "<fix summary>"
#     -> marks the bug fixed in Firestore so it stops showing in `list`
#   .\scripts\bugs.ps1 reopen <bugId>
#     -> flips back to 'new' (user said "still broken")
#
# The secret comes from functions/.env (same INGEST_SECRET the other
# diagnostic endpoints use). We parse it locally so we never embed it
# in the script itself.

$ErrorActionPreference = 'Stop'

$BaseUrl = 'https://us-central1-jarvis-78573.cloudfunctions.net'
$EnvFile = Join-Path $PSScriptRoot '..\functions\.env'

function Get-IngestSecret {
    if (-not (Test-Path $EnvFile)) {
        throw "functions/.env not found at $EnvFile"
    }
    $line = Get-Content $EnvFile | Where-Object { $_ -match '^INGEST_SECRET=' } | Select-Object -First 1
    if (-not $line) { throw 'INGEST_SECRET not in functions/.env' }
    # Strip key=, then strip surrounding quotes if any.
    $val = $line -replace '^INGEST_SECRET=', ''
    $val = $val -replace '^"', '' -replace '"$', ''
    return $val
}

function Invoke-Bugs-List {
    $secret = Get-IngestSecret
    # Encode secret for query string (# is special in URLs).
    $encoded = [System.Uri]::EscapeDataString($secret)
    $url = "$BaseUrl/listOpenBugs?secret=$encoded"
    $resp = Invoke-RestMethod -Uri $url -Method Get
    if ($resp.count -eq 0) {
        Write-Output "No open bugs. Clean slate."
        return
    }
    Write-Output "# $($resp.count) open bug(s)"
    Write-Output ""
    foreach ($b in $resp.bugs) {
        $sev = $b.severity.ToUpper().PadRight(6)
        $screen = if ($b.screen) { " [$($b.screen)]" } else { '' }
        $reported = if ($b.reported_at) {
            try { ([DateTime]$b.reported_at).ToString('dd MMM HH:mm') } catch { $b.reported_at }
        } else { '?' }
        Write-Output "[$sev] $($b.title)$screen"
        Write-Output "  id: $($b.id)"
        Write-Output "  reported: $reported  status: $($b.status)"
        # user_text = Pallav's verbatim chat message (authoritative).
        # description = Claude's paraphrase (legacy; only on older bugs).
        if ($b.user_text) {
            Write-Output "  USER'S EXACT WORDS:"
            Write-Output "    $($b.user_text)"
        } elseif ($b.description) {
            Write-Output "  (legacy paraphrase, raw text not captured):"
            Write-Output "    $($b.description)"
        }
        Write-Output ""
    }
}

function Invoke-Bugs-Fix {
    param([string]$BugId, [string]$FixNotes)
    if (-not $BugId) { throw 'Usage: bugs.ps1 fix <bugId> "<notes>"' }
    $secret = Get-IngestSecret
    $encoded = [System.Uri]::EscapeDataString($secret)
    $url = "$BaseUrl/markBugFixed?secret=$encoded"
    $body = @{
        bugId = $BugId
        fix_notes = $FixNotes
    } | ConvertTo-Json -Compress
    $resp = Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType 'application/json'
    if ($resp.ok) {
        Write-Output "Fixed $BugId"
    } else {
        Write-Output "Unexpected response: $($resp | ConvertTo-Json -Compress)"
    }
}

function Invoke-Bugs-Reopen {
    param([string]$BugId)
    if (-not $BugId) { throw 'Usage: bugs.ps1 reopen <bugId>' }
    $secret = Get-IngestSecret
    $encoded = [System.Uri]::EscapeDataString($secret)
    $url = "$BaseUrl/reopenBug?secret=$encoded"
    $body = @{ bugId = $BugId } | ConvertTo-Json -Compress
    $resp = Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType 'application/json'
    if ($resp.ok) { Write-Output "Reopened $BugId" }
}

# Command dispatch.
$cmd = $args[0]
switch ($cmd) {
    'list'   { Invoke-Bugs-List }
    'fix'    { Invoke-Bugs-Fix -BugId $args[1] -FixNotes ($args[2] -as [string]) }
    'reopen' { Invoke-Bugs-Reopen -BugId $args[1] }
    default  {
        Write-Output 'Usage:'
        Write-Output '  .\scripts\bugs.ps1 list'
        Write-Output '  .\scripts\bugs.ps1 fix <bugId> "<fix summary>"'
        Write-Output '  .\scripts\bugs.ps1 reopen <bugId>'
    }
}
