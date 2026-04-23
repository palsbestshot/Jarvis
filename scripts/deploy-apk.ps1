# scripts/deploy-apk.ps1 -- build + ship a new APK to Pallav's phone via
# Firebase App Distribution. One command per release.
#
# Flow:
#   1. Bump the `+N` build number in pubspec.yaml (versionCode). App Tester
#      on the phone only shows "Update available" when versionCode increments,
#      so this MUST happen for OTA delivery to work.
#   2. `flutter build apk --release` -- produces build/app/outputs/flutter-apk/app-release.apk
#   3. `firebase appdistribution:distribute` -- uploads to the 'pallav-phone'
#      group, triggers push notification on the phone's App Tester app.
#
# Release notes default to the latest git commit subject. Pass -Notes "..."
# to override.
#
# Usage:
#   .\scripts\deploy-apk.ps1
#   .\scripts\deploy-apk.ps1 -Notes "Fix widget feedback bug"
#   .\scripts\deploy-apk.ps1 -SkipBump    # for re-shipping same version

param(
    [string]$Notes,
    [switch]$SkipBump
)

$ErrorActionPreference = 'Stop'

$ProjectId = 'jarvis-78573'
# This is the app ID embedded in android/app/google-services.json -- matches
# the signing cert of `flutter build apk --release`.
$AppId = '1:546240967899:android:8c65d9e7e1ee96b7ca48fe'
$TesterGroup = 'pallav-phone'
$PubspecPath = Join-Path $PSScriptRoot '..\pubspec.yaml'
$ApkPath = Join-Path $PSScriptRoot '..\build\app\outputs\flutter-apk\app-release.apk'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

# -- 1. Bump versionCode in pubspec.yaml ------------------------------------
# Format is `version: 1.0.0+N` where N is the build number / versionCode.
function Bump-Version {
    $content = Get-Content $PubspecPath -Raw
    if ($content -notmatch '(?m)^version:\s*([\d\.]+)\+(\d+)') {
        throw "Couldn't find 'version: X.Y.Z+N' line in pubspec.yaml"
    }
    $semver = $Matches[1]
    $oldBuild = [int]$Matches[2]
    $newBuild = $oldBuild + 1
    $newLine = "version: $semver+$newBuild"
    $updated = $content -replace '(?m)^version:\s*[\d\.]+\+\d+', $newLine
    Set-Content -Path $PubspecPath -Value $updated -Encoding utf8 -NoNewline
    Write-Host "Bumped version $semver+$oldBuild -> $semver+$newBuild"
    return @{ semver = $semver; build = $newBuild }
}

# -- 2. Figure out release notes --------------------------------------------
function Get-DefaultNotes {
    Push-Location $RepoRoot
    try {
        $subject = git log -1 --pretty=%s 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $subject) { return 'no release notes' }
        return $subject.Trim()
    } finally { Pop-Location }
}

# -- 3. Run flutter build ----------------------------------------------------
function Invoke-FlutterBuild {
    Push-Location $RepoRoot
    try {
        Write-Host 'Running flutter build apk --release ...'
        & flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }
    } finally { Pop-Location }
    if (-not (Test-Path $ApkPath)) { throw "APK not produced at $ApkPath" }
}

# -- 4. Distribute via Firebase App Distribution ----------------------------
function Invoke-Distribute {
    param([string]$ReleaseNotes, [hashtable]$Version)
    $versionTag = if ($Version) { "$($Version.semver)+$($Version.build)" } else { '' }
    $fullNotes = if ($versionTag) { "$versionTag -- $ReleaseNotes" } else { $ReleaseNotes }
    Write-Host "Distributing APK with notes: $fullNotes"
    Push-Location $RepoRoot
    try {
        & firebase appdistribution:distribute $ApkPath `
            --app $AppId `
            --groups $TesterGroup `
            --release-notes $fullNotes `
            --project $ProjectId
        if ($LASTEXITCODE -ne 0) { throw "firebase appdistribution failed (exit $LASTEXITCODE)" }
    } finally { Pop-Location }
}

# -- Main ------------------------------------------------------------------
$versionInfo = $null
if (-not $SkipBump) { $versionInfo = Bump-Version }
if (-not $Notes) { $Notes = Get-DefaultNotes }

Invoke-FlutterBuild
Invoke-Distribute -ReleaseNotes $Notes -Version $versionInfo

Write-Host ''
Write-Host 'Done. Check Firebase App Tester on the phone in ~10s for the push.'
