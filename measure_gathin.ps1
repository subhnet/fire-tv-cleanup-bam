param(
  [string]$Serial = "192.168.29.20:5555",
  [string]$Adb = "C:\Users\subhr\AppData\Local\Temp\opencode\platform-tools\adb.exe",
  [string]$Out = "$PSScriptRoot\measure-gathin"
)
# Measures com.gathin.tvhome on the stick. Same methods as the stock baseline
# (Default Project\before\) so numbers are comparable:
#   - Home latency: 3x Home-from-Netflix, activity poll at 1s resolution
#   - Memory: 3x meminfo samples 30s apart AFTER a settle period
#   - Jank: gfxinfo reset -> 12x DPAD_RIGHT -> dump (launcher in focus)
#   - Netflix cold start: 3x force-stop -> am start -W
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Adb)) { $Adb = (Get-Command adb -ErrorAction SilentlyContinue).Source }
if (-not $Adb) { throw "adb not found. Install platform-tools or pass -Adb <path>" }
New-Item -ItemType Directory -Force -Path $Out | Out-Null
& $Adb connect $Serial | Out-Null
$stamp = Get-Date -Format "HH:mm:ss"

# ---- 1. Home latency: from Netflix, press Home, poll every second ----
Write-Host "`n[$stamp] HOME LATENCY (Netflix -> Home) x3"
& $Adb -s $Serial shell "am start -n com.netflix.ninja/.MainActivity" | Out-Null
Start-Sleep -Seconds 8
$lat = @()
1..3 | ForEach-Object {
  & $Adb -s $Serial shell "input keyevent KEYCODE_HOME"
  $t0 = Get-Date
  $hit = $null
  foreach ($i in 1..15) {
    Start-Sleep -Seconds 1
    $act = ((& $Adb -s $Serial shell "dumpsys activity activities | grep mResumedActivity") -join '')
    if ($act -match 'com\.gathin\.tvhome') { $hit = ((Get-Date) - $t0).TotalSeconds; break }
  }
  if ($hit) { "  run $_ : gathin home in $([math]::Round($hit,1))s" }
  else { "  run $_ : TIMEOUT (>15s) - $act" }
  $lat += $hit
  Start-Sleep -Seconds 3
}
if ($lat) { "  median: $([math]::Round((($lat | Sort-Object)[[int](($lat.Count-1)/2)]),1))s" }

# ---- 2. Settle 3 min, then memory x3 ----
Write-Host "`nSETTLING 3 MIN..."
Start-Sleep -Seconds 180
Write-Host "MEMORY SAMPLES x3 (30s apart):"
1..3 | ForEach-Object {
  & $Adb -s $Serial shell "grep -E 'MemAvailable|SwapFree' /proc/meminfo"
  Start-Sleep -Seconds 30
}

# ---- 3. Idle CPU ----
Write-Host "`nIDLE TOP:"
& $Adb -s $Serial shell "top -b -n 1 -m 10" | Select-Object -Last 12

# ---- 4. Launcher jank: focus grid, 12x RIGHT ----
& $Adb -s $Serial shell "input keyevent KEYCODE_HOME"
Start-Sleep -Seconds 4
& $Adb -s $Serial shell "dumpsys gfxinfo com.gathin.tvhome reset" | Out-Null
foreach ($k in 1..12) { & $Adb -s $Serial shell "input keyevent KEYCODE_DPAD_RIGHT"; Start-Sleep -Milliseconds 350 }
Write-Host "`nLAUNCHER JANK (12x DPAD_RIGHT):"
& $Adb -s $Serial shell "dumpsys gfxinfo com.gathin.tvhome | sed -n '/Total frames rendered/,/Slow issue draw commands/p'"

# ---- 5. Netflix cold start x3 ----
Write-Host "`nNETFLIX COLD START x3:"
$cs = @()
1..3 | ForEach-Object {
  & $Adb -s $Serial shell "am force-stop com.netflix.ninja" | Out-Null
  Start-Sleep -Seconds 2
  $out = (& $Adb -s $Serial shell "am start -W -n com.netflix.ninja/.MainActivity") -join ''
  $m = [regex]::Match($out, 'TotalTime:\s+(\d+)')
  if ($m.Success) { "  run $_ : $($m.Groups[1].Value)ms"; $cs += [int]$m.Groups[1].Value }
  Start-Sleep -Seconds 3
  & $Adb -s $Serial shell "input keyevent KEYCODE_HOME"
  Start-Sleep -Seconds 6
}
if ($cs) { "  median: $(($cs | Sort-Object)[[int](($cs.Count-1)/2)])ms" }

# ---- 6. Final home screenshot ----
cmd /c "`"$Adb`" -s $Serial exec-out screencap -p > `"$Out\gathin-home.png`""
Write-Host "`nSaved screenshot: $Out\gathin-home.png"
Write-Host "DONE."
