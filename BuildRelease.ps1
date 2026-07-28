param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) "releases")
)

$ErrorActionPreference = "Stop"

$tocPath = Join-Path $PSScriptRoot "PugzRaidTools.toc"
$versionLine = Select-String -LiteralPath $tocPath -Pattern '^## Version:\s*(.+)$'
if (-not $versionLine) {
    throw "Could not read the addon version from PugzRaidTools.toc."
}

$version = $versionLine.Matches[0].Groups[1].Value.Trim()
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "PugzRaidTools-release-" + [System.Guid]::NewGuid().ToString("N"))
$addonStage = Join-Path $stageRoot "PugzRaidTools"
$zipPath = Join-Path $outputRoot ("PugzRaidTools-v{0}.zip" -f $version)

try {
    New-Item -ItemType Directory -Path $addonStage -Force | Out-Null
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

    $publicRootFiles = @(
        "PugzRaidTools.toc",
        "CHANGELOG.md",
        "README.md",
        "LICENSE"
    )
    foreach ($name in $publicRootFiles) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) `
            -Destination $addonStage
    }

    Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.lua" -File |
        Copy-Item -Destination $addonStage
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "UI") `
        -Destination $addonStage -Recurse
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "Media") `
        -Destination $addonStage -Recurse

    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -LiteralPath $addonStage -DestinationPath $zipPath `
        -CompressionLevel Optimal
    Write-Output $zipPath
}
finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::GetTempPath())
    $resolvedStage = [System.IO.Path]::GetFullPath($stageRoot)
    $isTemporaryStage = $resolvedStage.StartsWith(
        $resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)
    if ($isTemporaryStage -and (Test-Path -LiteralPath $resolvedStage)) {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}
