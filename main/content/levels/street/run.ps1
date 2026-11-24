[CmdletBinding()]
param(
    [string]$GodotPath = $env:GODOT_BIN,
    [switch]$Editor,
    [switch]$ImportOnly,
    [string[]]$GameArguments = @()
)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
if (-not $GodotPath) {
    foreach ($name in @('godot', 'godot4')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue
        if ($command) { $GodotPath = $command.Source; break }
    }
}
if (-not $GodotPath) {
    $localEngine = 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe'
    if (Test-Path -LiteralPath $localEngine) { $GodotPath = $localEngine }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath)) {
    throw 'Godot was not found. Set GODOT_BIN or use: .\run.ps1 -GodotPath C:\path\Godot.exe'
}
Write-Host 'Importing project resources and script classes...'
# Always import: a class cache can exist while imported font data is missing.
& $GodotPath --headless --editor --path $projectRoot --import --quit
if ($LASTEXITCODE -ne 0) { throw "Godot import failed: exit $LASTEXITCODE" }
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.godot/global_script_class_cache.cfg'))) {
    throw 'Godot did not create the script class cache.'
}
foreach ($font in Get-ChildItem -LiteralPath (Join-Path $projectRoot 'assets/fonts') -Filter '*.ttf') {
    $metadata = $font.FullName + '.import'
    if (-not (Test-Path -LiteralPath $metadata)) { throw "Missing font import: $($font.Name)" }
    $match = [regex]::Match([IO.File]::ReadAllText($metadata), '(?m)^path="res://([^"]+)"')
    if (-not $match.Success -or -not (Test-Path -LiteralPath (Join-Path $projectRoot $match.Groups[1].Value))) {
        throw "Font data was not imported: $($font.Name). Open project.godot in Godot and let import finish."
    }
}
if ($ImportOnly) { Write-Host 'Import verified.'; exit 0 }
$launchArgs = @('--path', $projectRoot)
if ($Editor) { $launchArgs += '--editor' }
& $GodotPath @launchArgs @GameArguments
exit $LASTEXITCODE
