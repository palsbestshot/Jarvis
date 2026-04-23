# scripts/deploy-web.ps1 -- build + deploy Rakhi's Jarvis PWA.
#
# Pallav's Android APK is NOT touched by this script (see deploy-apk.ps1
# for that). This script is for the Flutter Web PWA at
# https://jarvis-78573.web.app -- Rakhi's "Add to Home Screen" target.
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
#   1. Back up real env.json to env.json.real.bak
#   2. Write a stripped {} env.json so nothing bundles into the JS
#   3. flutter build web --dart-define-from-file=env.web.json
#   4. Restore env.json from backup (always -- even on failure)
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
        # PowerShell splits unquoted comma-separated args; --only expects a
        # single string so quote it even for the single-target case.
        & firebase deploy --only "functions" --project $ProjectId
        if ($LASTEXITCODE -ne 0) { throw "firebase deploy failed (exit $LASTEXITCODE)" }
    } finally { Pop-Location }
    Write-Host ''
    Write-Host 'Functions deployed.' -ForegroundColor Green
    exit 0
}

# -- Pre-flight checks -------------------------------------------------------
if (-not (Test-Path $EnvRealPath)) {
    throw "env.json not found at $EnvRealPath. Aborting before any changes."
}
if (-not (Test-Path $EnvWebPath)) {
    throw "env.web.json not found at $EnvWebPath. This file carries the web INGEST_SECRET and VAPID_PUBLIC_KEY -- create it first (see the plan / CLAUDE.md)."
}

# -- 1. Swap env.json to {} so nothing leaks into the bundle ----------------
Write-Step 'Backing up env.json to env.json.real.bak and writing stripped placeholder'
Copy-Item -Path $EnvRealPath -Destination $EnvBackupPath -Force
Set-Content -Path $EnvRealPath -Value '{}' -Encoding utf8 -NoNewline

$buildFailed = $false
try {
    # -- 2. Flutter build web -----------------------------------------------
    Write-Step 'flutter build web --release --pwa-strategy=offline-first --dart-define-from-file=env.web.json'
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
        throw "build/web/index.html missing -- flutter build did not produce output."
    }

    # -- 2a. Patch flutter_bootstrap.js to host Flutter inside
    # #flutter-root instead of document.body ------------------------------
    # Flutter's auto-generated bootstrap calls _flutter.loader.load({
    #   serviceWorkerSettings: ... }) without a hostElement, so Flutter
    # appends its <flutter-view> to document.body at position:fixed with
    # full-viewport bounds. On iOS Safari PWA that causes a touch-offset
    # bug: content visually masked by the notch / home-indicator, but
    # the hit-test canvas still runs edge-to-edge.
    #
    # We patch the generated file to add
    #   config: { hostElement: document.querySelector('#flutter-root') }
    # so Flutter renders inside our wrapper div that's inset via
    # env(safe-area-inset-*) CSS. Visual and tap coordinates then align.
    #
    # Idempotent: if already patched (re-run, cached build dir), skip.
    Write-Step 'Patching flutter_bootstrap.js with hostElement=#flutter-root'
    $bootstrapPath = Join-Path $WebBuildDir 'flutter_bootstrap.js'
    if (-not (Test-Path $bootstrapPath)) {
        throw "build/web/flutter_bootstrap.js missing -- can't inject hostElement config."
    }
    $bootstrap = Get-Content $bootstrapPath -Raw
    if ($bootstrap.Contains("hostElement: document.querySelector('#flutter-root')")) {
        Write-Host '  already patched, skipping' -ForegroundColor DarkGray
    } else {
        $needle = '_flutter.loader.load({'
        $replacement = "_flutter.loader.load({`n  config: { hostElement: document.querySelector('#flutter-root') },"
        if (-not $bootstrap.Contains($needle)) {
            throw "Couldn't find '$needle' in flutter_bootstrap.js -- has Flutter's loader API changed? Check build/web/flutter_bootstrap.js and update this patch."
        }
        $patched = $bootstrap.Replace($needle, $replacement)
        # UTF8 without BOM so the browser's parser doesn't see a stray
        # byte-order-mark character at the top of the JS file.
        [System.IO.File]::WriteAllText($bootstrapPath, $patched, (New-Object System.Text.UTF8Encoding $false))
        Write-Host '  patched.' -ForegroundColor DarkGray
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
    Write-Host 'Web build failed -- env.json restored, aborting before deploy.' -ForegroundColor Red
    exit 1
}

if ($BuildOnly) {
    Write-Host ''
    Write-Host "Build finished at $WebBuildDir -- not deploying (-BuildOnly)." -ForegroundColor Green
    exit 0
}

# -- 4. Firebase deploy ------------------------------------------------------
# Quote the --only target list. PowerShell splits `hosting,functions` on the
# comma otherwise, and firebase reads them as two separate flag values which
# produces "No targets in firebase.json match".
Write-Step 'firebase deploy --only "hosting,functions"'
Push-Location $RepoRoot
try {
    & firebase deploy --only "hosting,functions" --project $ProjectId
    if ($LASTEXITCODE -ne 0) { throw "firebase deploy failed (exit $LASTEXITCODE)" }
} finally { Pop-Location }

Write-Host ''
Write-Host "Done. PWA live at https://$ProjectId.web.app" -ForegroundColor Green
Write-Host "Rakhi opens that URL in Safari, taps Share, then 'Add to Home Screen'."
