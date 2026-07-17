# Compara la telemetria de dificultad baseline vs after por configuracion.
# Uso: powershell -File tests/compare_telemetry.ps1
$dir = "$env:APPDATA\Godot\app_userdata\CatsVsZombieDogs\telemetry"
$configs = @("solo_0", "solo_1", "solo_2", "coop_1", "coop_2")
foreach ($cfg in $configs) {
    $base = Join-Path $dir "${cfg}_baseline.json"
    $after = Join-Path $dir "${cfg}_after.json"
    if (-not (Test-Path $after)) { continue }
    Write-Output ""
    Write-Output "===== $cfg (antes -> despues) ====="
    $b = if (Test-Path $base) { (Get-Content $base -Raw | ConvertFrom-Json).rows } else { @() }
    $a = (Get-Content $after -Raw | ConvertFrom-Json).rows
    $bmap = @{}
    foreach ($r in $b) { $bmap[[int]$r.minute] = $r }
    Write-Output ("min | score        | hp mult      | dmg mult     | spd mult     | intervalo    | vivos     | elites  | kpm")
    foreach ($r in $a) {
        $m = [int]$r.minute
        $o = $bmap[$m]
        if ($null -ne $o) {
            Write-Output ("{0,3} | {1,5} -> {2,-5} | {3,5} -> {4,-5} | {5,5} -> {6,-5} | {7,5} -> {8,-5} | {9,5} -> {10,-5} | {11,3} -> {12,-3} | {13,2} -> {14,-2} | {15,3} -> {16,-3}" -f `
                $m, $o.score, $r.score, $o.health_mult, $r.health_mult, $o.damage_mult, $r.damage_mult, `
                $o.speed_mult, $r.speed_mult, $o.spawn_interval, $r.spawn_interval, $o.alive, $r.alive, `
                $o.elites, $r.elites, $o.kills_per_min, $r.kills_per_min)
        } else {
            Write-Output ("{0,3} |       -> {1,-5} |       -> {2,-5} |       -> {3,-5} |       -> {4,-5} |       -> {5,-5} |     -> {6,-3} |    -> {7,-2} |     -> {8,-3}" -f `
                $m, $r.score, $r.health_mult, $r.damage_mult, $r.speed_mult, $r.spawn_interval, $r.alive, $r.elites, $r.kills_per_min)
        }
    }
}
