param(
  [string]$Serial = "192.168.29.20:5555",
  [string]$Adb = "C:\Users\subhr\AppData\Local\Temp\opencode\platform-tools\adb.exe",
  [string]$Backup = ""
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Adb)) { $Adb = (Get-Command adb -ErrorAction SilentlyContinue).Source }
if (-not $Adb) { throw "adb not found. Install platform-tools or pass -Adb <path>" }
& $Adb connect $Serial | Out-Null

# Find the newest backup if none given.
if (-not $Backup) {
  $Backup = Get-ChildItem -Path $PSScriptRoot -Filter "backup-*.txt" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if ($Backup -and (Test-Path $Backup)) {
  $saver = (Select-String -Path $Backup -Pattern '^screensaver_components=(.*)$').Matches.Groups[1].Value
  Write-Host "Restoring screensaver_components='$saver'"
  if ($saver -eq "" -or $saver -eq "null") {
    & $Adb -s $Serial shell settings put secure screensaver_components null
  } else {
    & $Adb -s $Serial shell settings put secure screensaver_components "$saver"
  }
} else {
  Write-Host "No backup file found; clearing screensaver_components."
  & $Adb -s $Serial shell settings put secure screensaver_components null
}

# Disable the Home redirect. MUST be the literal `null`, NOT "": Fire OS
# resurrects an empty string (and the binding) on the next boot. Verified on
# AFTSSS Fire OS 7.7.1.7 during the tvbox.home revert.
& $Adb -s $Serial shell settings put secure enabled_accessibility_services null
& $Adb -s $Serial shell settings put secure accessibility_enabled 0

# Remove the launcher.
Write-Host "Uninstalling com.gathin.tvhome..."
& $Adb -s $Serial uninstall com.gathin.tvhome

Write-Host "`nState (all three should read null/0 and no service bound):"
& $Adb -s $Serial shell "settings get secure enabled_accessibility_services; settings get secure accessibility_enabled; settings get secure screensaver_components"
& $Adb -s $Serial shell "dumpsys accessibility | grep -c 'gathin'"
Write-Host "`nReboot the stick once to confirm the redirect stays dead, then turn ADB debugging off."
