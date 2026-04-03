$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sourceRoot = 'D:\fccc\img'
$targetRoot = Join-Path $root 'assets\shop_catalog'

$folderMap = @{
    'Booster  utility item PNGs' = 'boosters'
    'Bundle cover PNGs' = 'bundles'
    'Chat bubble  chat cosmetic PNGs' = 'chat_bubbles'
    'Collectibles  capsules PNGs' = 'collectibles'
    'Mic aura  voice effect PNGs' = 'mic_auras'
    'Nameplate  identity cosmetic PNGs' = 'nameplates'
    'profile frame png' = 'frames'
    'Room entry effect PNGs' = 'entry_effects'
    'Shop system UI PNGs' = 'ui'
}

foreach ($entry in $folderMap.GetEnumerator()) {
    $sourceDir = Join-Path $sourceRoot $entry.Key
    $targetDir = Join-Path $targetRoot $entry.Value

    if (-not (Test-Path -LiteralPath $sourceDir)) {
        throw "Missing source folder: $sourceDir"
    }

    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

    Get-ChildItem -LiteralPath $sourceDir -Filter '*.png' -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $targetDir $_.Name) -Force
    }
}

Write-Host "Shop asset sync complete: $sourceRoot -> $targetRoot"
