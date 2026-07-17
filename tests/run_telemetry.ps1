# Corre la telemetria de dificultad en las 5 configuraciones requeridas.
# Uso: powershell -File tests/run_telemetry.ps1 <sufijo>   (p.ej. "baseline" o "after")
param([string]$Suffix = "baseline")
$godot = "C:\Users\ad\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"
$proj = Split-Path $PSScriptRoot -Parent
$configs = @("solo:0", "solo:1", "solo:2", "coop:1", "coop:2")
foreach ($cfg in $configs) {
    $name = ($cfg -replace ":", "_")
    $env:TELEMETRY_MODE = $cfg
    $env:TELEMETRY_MINUTES = "20"
    $env:TELEMETRY_SCALE = "12"
    $env:TELEMETRY_OUT = "${name}_${Suffix}"
    Write-Output "=== $cfg ($Suffix) ==="
    & $godot --headless --path $proj res://tests/TestDifficultyTelemetry.tscn 2>$null | Select-String -Pattern "MIN |TELEMETRY"
}
Write-Output "TELEMETRY SUITE DONE ($Suffix)"
