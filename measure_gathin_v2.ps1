param(
  [string]$Serial = "192.168.29.20:5555",
  [string]$Adb = "C:\Users\subhr\AppData\Local\Temp\opencode\platform-tools\adb.exe",
  [string]$Out = "$PSScriptRoot\measure-gathin"
)
# Post-tuning re-measure. Compares against measure-gathin\results-live.txt (pre-tuning)
# and baseline-stock-reverted.txt (stock). No per-second dumpsys polling for latency.
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Adb)) { $Adb = (Get-Command adb -ErrorAction SilentlyContinue).Source }
if (-not $Adb) { throw "adb not found. Install platform-tools or pass -Adb <path>" }
New-Item -ItemType Directory -Force -Path $Out | Out-Null
& $Adb connect $Serial | Out-Null

function Dump-Jank($label) {
  & $Adb -s $Serial shell "dumpsys gfxinfo com.gathin.tvhome reset" | Out-Null
  foreach ($k in 1..12) { & $Adb -s $Serial shell "input keyevent KEYCODE_DPAD_RIGHT"; Start-Sleep -Milliseconds 350 }
  "=== JANK: $label (12x DPAD_RIGHT) ==="
  & $Adb -s $Serial shell "dumpsys gfxinfo com.gathin.tvhome | sed -n '/Total frames rendered/,/Slow issue draw commands/p'"
}

# 0. Home, settle after the reinstall.
& $Adb -s $Serial shell "input keyevent KEYCODE_HOME"
Start-Sleep -Seconds 8

# 1. Dock-row jank (same path as the pre-tuning test).
Dump-Jank "dock row"

# 2. Grid-row jank: DOWN twice to leave the dock, then across.
& $Adb -s $Serial shell "input keyevent KEYCODE_DPAD_DOWN"
Start-Sleep -Milliseconds 600
& $Adb -s $Serial shell "input keyevent KEYCODE_DPAD_DOWN"
Start-Sleep -Seconds 2
Dump-Jank "row below dock"

# 3. Home latency via logcat timestamps x2 (no polling).
& $Adb -s $Serial shell "am start -n com.netflix.ninja/.MainActivity" | Out-Null
Start-Sleep -Seconds 8
1..2 | ForEach-Object {
  & $Adb -s $Serial shell "logcat -c"
  $t0 = ((& $Adb -s $Serial shell "date +%s.%3N") -join '').Trim()
  & $Adb -s $Serial shell "input keyevent KEYCODE_HOME"
  Start-Sleep -Seconds 10
  "--- home latency run $_ (Home pressed at unix $t0) ---"
  & $Adb -s $Serial shell "logcat -d -v concise" | Select-String -Pattern "HomeRedirect|Displayed com\.gathin"
}

# 4. Netflix cold start x2 (rule: within 15% of stock 1056 ms).
1..2 | ForEach-Object {
  & $Adb -s $Serial shell "am force-stop com.netflix.ninja" | Out-Null
  Start-Sleep -Seconds 2
  $out = (& $Adb -s $Serial shell "am start -W -n com.netflix.ninja/.MainActivity") -join ''
  $m = [regex]::Match($out, 'TotalTime:\s+(\d+)')
  "netflix cold run $_ : $($m.Groups[1].Value)ms"
  Start-Sleep -Seconds 3
  & $Adb -s $Serial shell "input keyevent KEYCODE_HOME"
  Start-Sleep -Seconds 5
}

# 5. Memory + idle CPU (kswapd0 check).
"--- meminfo ---"
& $Adb -s $Serial shell "grep -E 'MemAvailable|SwapFree' /proc/meminfo"
"--- idle top ---"
& $Adb -s $Serial shell "top -b -n 1 -m 8" | Select-Object -Last 10

# 6. Screenshot for the record.
cmd /c "`"$Adb`" -s $Serial exec-out screencap -p > `"$Out\gathin-tuned-home.png`""
"DONE"
