# AGENTS.md — fire-tv-cleanup-bam

Guidance for coding agents working in this repository. This is a **personal fork** of
[itsmeterrylin/fire-tv-cleanup](https://github.com/itsmeterrylin/fire-tv-cleanup), actively
installed on a specific Fire TV device. Read this before making changes.

## Project overview

- **What:** A debloat + custom launcher setup for Android/Google/Fire TV. The launcher
  (`com.gathin.tvhome`, package in `launcher/`) is a native Java app (RecyclerView, no WebView)
  with a dock, app grid, time-of-day backgrounds, and a photo screensaver (`PhotoDream`).
- **Fork purpose:** Tuned for a low-RAM Fire TV stick. Contains device-specific config,
  performance fixes, Windows (PowerShell) tooling, and on-device measurement records.
- **Upstream:** `ab4d9bf` is the merge base. Prefer minimal, revertable diffs to upstream
  launcher code; put device-specific tooling/docs in new files at repo root.

## Target device (verified)

| | |
|---|---|
| Model | Fire TV Stick 4K Max — **AFTSSS** |
| Fire OS / Android | 7.7.1.7 / Android 9 (SDK 28), `armeabi-v7a` |
| RAM / storage | 922 MB RAM, ~5 GB `/data` |
| LAN address (when tested) | `192.168.29.20:5555` (ADB over network; changes with DHCP) |
| State | `com.gathin.tvhome` installed & active (Home redirect + PhotoDream screensaver) |

Always confirm connectivity before device operations: `adb connect <ip>:5555` and
`adb devices`. ADB debugging must be enabled on the TV; it can turn off after restarts.

## Repo map

```
launcher/                  # Android app (com.gathin.tvhome)
  app/src/main/java/com/gathin/tvhome/
    MainActivity.java      # home UI, clock, dock/grid, focus, "more below" hint
    HomeRedirectService.java # accessibility service: bounces Amazon home -> this launcher
    PhotoDream.java        # screensaver (DreamService)
    AppAdapter.java        # app discovery, dock pinning (SharedPreferences "tvhome"/"dock")
  app/src/main/res/
    values/config.xml      # dock_apps, hidden_apps, live_tv_package, columns (EDIT THIS)
    layout/activity_main.xml
    drawable-nodpi/        # bg_morning/afternoon/evening/night, bg_*_india, saver_01-12
  build.gradle, gradlew*   # AGP 8.5.2, compileSdk 34, minSdk 26, targetSdk 29
tools/                     # upstream ADB helpers (tv.py, b64push.py)
examples/                  # per-device debloat lists
README-BAM.md              # fork summary: changes, measured results, install/revert
TRIAL-NOTES.md             # chronological on-device trial record (source of truth for numbers)
CREDITS.md, saver-credits.json  # image/font attribution (keep accurate when swapping assets)
install_gathin.ps1         # Windows install + enable redirect/screensaver (backs up settings)
restore_gathin.ps1         # full revert to stock (reboot-proof)
measure_gathin*.ps1        # measurement suites
baseline-stock-reverted.txt, measure-gathin/  # baseline + results + screenshots
backup-192.168.29.20.txt   # pre-install settings for this stick (used by restore)
```

## Build & install (Windows, this machine)

Toolchains live in temp locations (may need re-download on a new machine):
- JDK 17 (full, with `instrument.dll`): `C:\Users\subhr\AppData\Local\Temp\opencode\jdk17-full\jdk-17.0.21+9`
- Gradle 8.9: `C:\Users\subhr\AppData\Local\Temp\opencode\gradle-8.9\bin\gradle.bat`
- Android SDK: `C:\Users\subhr\AppData\Local\Temp\opencode\toolchain-sdk` (platform 34, build-tools 34)

`launcher/local.properties` is gitignored — create it if missing:
```
sdk.dir=C:/Users/subhr/AppData/Local/Temp/opencode/toolchain-sdk
tvhome.userName=Subhransu
```

Build:
```powershell
$env:JAVA_HOME = "C:\Users\subhr\AppData\Local\Temp\opencode\jdk17-full\jdk-17.0.21+9"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
cd launcher
& "C:\Users\subhr\AppData\Local\Temp\opencode\gradle-8.9\bin\gradle.bat" assembleDebug --console=plain --no-daemon
# APK: launcher\app\build\outputs\apk\debug\app-debug.apk
```

Install (backs up settings once, enables redirect + screensaver):
```powershell
pwsh -NoProfile -File .\install_gathin.ps1 -Serial 192.168.29.20:5555
```

**After every `adb install -r` the accessibility binding is silently dropped.** Always
re-enable it:
```sh
adb shell settings put secure enabled_accessibility_services com.gathin.tvhome/com.gathin.tvhome.HomeRedirectService
adb shell settings put secure accessibility_enabled 1
```

## Revert to stock (fully tested)

```powershell
pwsh -NoProfile -File .\restore_gathin.ps1 -Serial 192.168.29.20:5555
```
Then reboot once to confirm, and turn ADB debugging off.

## Critical Fire OS gotchas (verified on AFTSSS)

1. **`enabled_accessibility_services` must be set to the literal `null`, never `""`.**
   An empty string is silently resurrected (with the binding) on the next boot; `null` sticks.
   This applies to revert/disable. Verified across multiple reboots.
2. **Reinstall drops the accessibility service binding** — always re-put the setting and
   `accessibility_enabled 1` after install.
3. **Home takeover is a bounce, not a real default-home:** Fire OS routes Home to Amazon's
   launcher by intent. `HomeRedirectService` listens for `TYPE_WINDOW_STATE_CHANGED` on
   `com.amazon.tv.launcher`/`HomeActivity_vNext` and brings `MainActivity` forward. Expect a
   ~2–2.7 s Amazon-home flash (OS cost) + ~0.3–0.7 s launcher first frame. This is inherent.
4. **Slow boot:** on this stick the accessibility service can bind ~10+ minutes after power-on
   (boot thrash). `onServiceConnected()` must bring the launcher forward unconditionally —
   do **not** gate on a boot-time window (was the root cause of "nothing on power-on").
5. **Screensaver has two keys:** `screensaver_components` (idle) and
   `screensaver_default_component` (sleep/TV-off). Set both to
   `com.gathin.tvhome/com.gathin.tvhome.PhotoDream`, and restore both on revert.
6. **"Pressing Home while already on Amazon home" produces no window-state change** — so no
   redirect event fires. The service must have already brought the launcher forward (see #4).
7. **`pm disable`/uninstall system packages:** never. Debloat uses `pm disable-user --user 0`.
8. **922 MB RAM:** keep the launcher lean. Avoid WebViews, infinite animations, large bitmaps
   decoded on UI thread, and per-resume heavy work. Prefer `transform/opacity`-style changes,
   cache PackageManager results across warm resumes, and never hold resources while apps run.

## Configuring the launcher

- **Dock & grid:** `launcher/app/src/main/res/values/config.xml`
  - `dock_apps`: starting dock order (max = `columns`). After first run the user's on-TV
    pin/reorder is saved in SharedPreferences (`tvhome`/`dock`) and overrides this.
  - `hidden_apps`: packages never shown as tiles.
  - `columns`: grid columns and max dock slots (currently 6).
- **Time-of-day backgrounds:** `R.drawable.bg_morning_india`, `bg_afternoon_india`,
  `bg_evening_india`, `bg_night_india` (wired in `MainActivity.BACKGROUNDS`). Morning 5–12,
  afternoon 12–17, evening 17–22, night otherwise.
- **Screensaver photos:** `drawable-nodpi/saver_01.jpg`–`saver_12.jpg`, shuffled/cycled by
  `PhotoDream`.
- **To reset the dock to config defaults on the TV:** clear app data
  (`pm clear com.gathin.tvhome`) — note this also resets on-device pin order; re-enable the
  accessibility binding and screensaver after clearing.

## Asset & attribution rules

- Keep images ~1920×1080 and reasonably compressed (this stick is memory-constrained).
- When adding/replacing photos, update **`CREDITS.md`** and, for screensaver images,
  **`saver-credits.json`** with source, author, and license. Prefer freely licensed sources
  (Wikimedia Commons, Unsplash license, CC0/CC BY/CC BY-SA) with verifiable attribution.
- Do not add trademarked logo bitmaps to the repo (see upstream README/tools).

## Performance & measurement

- Baseline and all trial numbers: `baseline-stock-reverted.txt`, `TRIAL-NOTES.md`,
  `measure-gathin/results-*.txt`.
- When optimizing, measure honestly (gfxinfo jank, `dumpsys meminfo`, `am start -W` cold
  starts, idle `top` for kswapd0/iowait) and compare against the recorded baseline.
  `home-latency.sh` / logcat `Displayed` timestamps are more accurate for Home latency than
  polling `dumpsys` (polling itself loads the stick).
- This fork's tuning (grid 33% janky / 10 ms p50, Netflix ~1.05 s, ~275 MB MemAvailable idle,
  no kswapd0) is the bar — don't regress it.

## Git workflow

- Repo: https://github.com/subhnet/fire-tv-cleanup-bam (`origin`). Branch `main` tracks
  upstream base + fork commits.
- Make commits atomic and revertable (config, launcher code, tooling/docs separately).
- Do **not** commit build outputs, `local.properties`, `.gradle/`, or device-private dumps
  beyond what's already intentionally tracked. Temp toolchains stay under
  `C:\Users\subhr\AppData\Local\Temp\opencode\`.

## When the user says "install"

Build, `adb install -r` the APK, re-enable `HomeRedirectService` binding + `accessibility_enabled`,
ensure both screensaver keys point to `PhotoDream`, and (re)start `MainActivity`. Confirm
the resumed activity and the secure settings values. Do not claim success without checking.
