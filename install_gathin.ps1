param(
  [string]$Serial = "192.168.29.20:5555",
  [string]$Adb = "C:\Users\subhr\AppData\Local\Temp\opencode\platform-tools\adb.exe",
  [string]$Apk = "$PSScriptRoot\launcher\app\build\outputs\apk\debug\app-debug.apk"
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Adb)) { $Adb = (Get-Command adb -ErrorAction SilentlyContinue).Source }
if (-not $Adb) { throw "adb not found. Install platform-tools or pass -Adb <path>" }
if (-not (Test-Path $Apk)) { throw "APK not found: $Apk (run: gradlew.bat assembleDebug)" }
$shots = "$PSScriptRoot\measure-gathin"
New-Item -ItemType Directory -Force -Path $shots | Out-Null
& $Adb connect $Serial | Out-Null

# 1. Back up the settings we are about to change (restore_gathin.ps1 reads these back).
#    Only on first run: a re-install must NOT overwrite the original (pre-gathin) values.
$backup = "$PSScriptRoot\backup-$($Serial.Split(':')[0]).txt"
if (Test-Path $backup) {
  Write-Host "Backup $(Split-Path $backup -Leaf) exists - keeping original values (re-install run)."
} else {
  $saver = ((& $Adb -s $Serial shell settings get secure screensaver_components) -join '').Trim()
  $acs   = ((& $Adb -s $Serial shell settings get secure enabled_accessibility_services) -join '').Trim()
  "screensaver_components=$saver"  | Set-Content -Path $backup -Encoding ascii
  "enabled_accessibility_services=$acs" | Add-Content -Path $backup -Encoding ascii
  Write-Host "Backed up to $backup (screensaver='$saver', accessibility='$acs')"
}

# 2. Install.
Write-Host "Installing com.gathin.tvhome..."
& $Adb -s $Serial install -r $Apk

# 3. Grant on-device toggle permission (Menu on Settings can then turn the redirect on/off).
& $Adb -s $Serial shell pm grant com.gathin.tvhome android.permission.WRITE_SECURE_SETTINGS

# 4. Enable the Home redirect + photo screensaver (Fire TV path of build-and-install.sh).
& $Adb -s $Serial shell settings put secure enabled_accessibility_services com.gathin.tvhome/com.gathin.tvhome.HomeRedirectService
& $Adb -s $Serial shell settings put secure accessibility_enabled 1
& $Adb -s $Serial shell settings put secure screensaver_components com.gathin.tvhome/com.gathin.tvhome.PhotoDream

# 5. Open it once.
& $Adb -s $Serial shell am start -n com.gathin.tvhome/.MainActivity | Out-Null
Start-Sleep -Seconds 4
# cmd /c for the binary redirect: PowerShell `>` re-encodes and corrupts PNGs.
cmd /c "`"$Adb`" -s $Serial exec-out screencap -p > `"$shots\installed-home.png`""
Write-Host "`nState:"
& $Adb -s $Serial shell "settings get secure enabled_accessibility_services; settings get secure accessibility_enabled; settings get secure screensaver_components"
Write-Host "Screenshot: measure-gathin\installed-home.png  |  Undo: .\restore_gathin.ps1 -Serial $Serial"
