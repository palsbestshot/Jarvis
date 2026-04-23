# scripts/deploy-web.ps1 -- build + deploy Rakhi's Jarvis PWA.
#
# Pallav's Android APK is not touched by this script (see deploy-apk.ps1
# for that). This script is for the Flutter Web PWA at
# https://jarvis-78573.web.app — Rakhi's "Add to Home Screen" target.
#
# Why the env swap: env.json lives in pubspec.yaml's `assets:` list so
# it ships with the Android APK. Flutter Web bundles every asset into
# the browser JS. If we didn't swap env.json here, the provider API
# keys (OpenAI, Anthropic) would be visible in devtools on the deployed
# site. Server-side we call those providers via the aiChat /
# aiTranscribe / aiTTS Cloud Functions instead, authenticated with
# INGEST_SECRET injected from env.web.json.
#
# Flow:
#   1. Back up real env.json to env.json.real
#   2. Write a stripped {} env.json so nothing bundles into the JS
#   3. flutter build web --dart-define-from-file=env.web.json
#   4. Restore env.json from backup (always — even on failure)
#   5. firebase deploy --only hosting,functions
#
# Usage:
#   .\scripts\deploy-web.ps1                 # build + deploy
#   .\scripts\deploy-web.ps1 -BuildOnly      # build, skip deploy
#   .\scripts\deploy-web.ps1 -FunctionsOnly  # skip web build, deploy functions only

param(
    [switch]$BuildOnly,
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$EnvRealPath = Join-Path $RepoRoot 'env.json'
$EnvBackupPath = Join-Path $RepoRoot 'env.json.real.bak'
$EnvWebPath = Join-Path $RepoRoot 'env.web.json'
$WebBuildDir = Join-Path $RepoRoot 'build\web'
$ProjectId = 'jarvis-78573'

function Write-Step($text) { Write-Host "==> $text" -ForegroundColor Cyan }

# -- Functions-only fast path -----------------------------------------------
if ($FunctionsOnly) {
    Write-Step 'Deploying Cloud Functions only'
    Push-Location $RepoRoot
    try {
        & firebase deploy --only functions --project $ProjectId
        if ($LASTEXITCODE -ne 0) { throw "firebase deploy failed (exit $LASTEXITCODE)" }
    } finally { Pop-Location }
    Write-Host ''
    Write-Host 'Functions deployed.' -ForegroundColor Green
    exit 0
}

# -- Pre-flight checks -------------------------------------------------------
if (-not (Test-Path $EnvRealPath)) {
    throw "env.json not found at $EnvRealPath. Can't proceed — aborting before any changes."
}
if (-not (Test-Path $EnvWebPath)) {
    throw "env.web.json not found at $EnvWebPath. This file carries the web INGEST_SECRET + VAPID_PUBLIC_KEY — create it first (see the plan / CLAUDE.md)."
}

# -- 1. Swap env.json → {} so nothing leaks into the bundle -----------------
Write-Step 'Backing up env.json → env.json.real.bak and writing stripped placeholder'
Copy-Item -Path $EnvRealPath -Destination $EnvBackupPath -Force
Set-Content -Path $EnvRealPath -Value '{}' -Encoding utf8 -NoNewline

$buildFailed = $false
try {
    # -- 2. Flutter build web -----------------------------------------------
    Write-Step 'flutter build web --pwa-strategy=offline-first --release --dart-define-from-file=env.web.json'
    Push-Location $RepoRoot
    try {
        & flutter build web `
            --release `
            --pwa-strategy=offline-first `
            --dart-define-from-file=env.web.json
        if ($LASTEXITCODE -ne 0) {
            $buildFailed = $true
            throw "flutter build web failed (exit $LASTEXITCODE)"
        }
    } finally { Pop-Location }

    if (-not (Test-Path (Join-Path $WebBuildDir 'index.html'))) {
        throw "build/web/index.html missing — flutter build didn't produce output."
    }
} finally {
    # -- 3. Restore env.json NO MATTER WHAT ---------------------------------
    # This is the most important line in this script. If a build error
    # leaves env.json as `{}`, Pallav's next APK build would bundle an
    # empty env and his chat would silently break. The finally block
    # guarantees restoration even on ctrl-c.
    Write-Step 'Restoring original env.json from backup'
    Move-Item -Path $EnvBackupPath -Destination $EnvRealPath -Force
}

if ($buildFailed) {
    Write-Host 'Web build failed — env.json restored, aborting before deploy.' -ForegroundColor Red
    exit 1
}

if ($BuildOnly) {
    Write-Host ''
    Write-Host "Build finished at $WebBuildDir — not deploying (-BuildOnly)." -ForegroundColor Green
    exit 0
}

# -- 4. Firebase deploy ------------------------------------------------------
Write-Step 'firebase deploy --only hosting,functions'
Push-Location $RepoRoot
try {
    & firebase deploy --only hosting,functions --project $ProjectId
    if ($LASTEXITCODE -ne 0) { throw "firebase deploy failed (exit $LASTEXITCODE)" }
} finally { Pop-Location }

Write-Host ''
Write-Host "Done. PWA live at https://$ProjectId.web.app" -ForegroundColor Green
Write-Host "Rakhi opens that URL in Safari → Share → 'Add to Home Screen'."
