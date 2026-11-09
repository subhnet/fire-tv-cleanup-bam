# fire-tv-cleanup-bam — my Fire TV Stick 4K Max build

Personal fork of [itsmeterrylin/fire-tv-cleanup](https://github.com/itsmeterrylin/fire-tv-cleanup),
tuned and verified on-device for a **Fire TV Stick 4K Max (AFTSSS, Fire OS 7.7.1.7,
Android 9, 922 MB RAM)** on Windows. The launcher (`com.gathin.tvhome`) is currently
**installed and active** on the stick; everything here is reversible.

The full chronological trial record (what was measured, what failed, what was tuned,
and the decision rule) is in [`TRIAL-NOTES.md`](TRIAL-NOTES.md). This file is the summary.

## Changes vs upstream

Upstream code is untouched except for two files; all other changes are new files
on top. Each change is its own commit, so `git revert` works per-change.

### 1. `launcher/app/src/main/res/values/config.xml` — device adaptation
- Dock: **Netflix, SmartTube (YouTube), Disney+ Hotstar, Amazon Music** (this stick's apps).
- `com.amazon.bueller.music` (Amazon Music) removed from `hidden_apps` — it is the music tile.
- `live_tv_package` emptied: `com.amazon.tv.livetv` is disabled on this stick.

### 2. `launcher/.../MainActivity.java` — performance tuning for 922 MB sticks
Measured jank drove five targeted fixes (details in `TRIAL-NOTES.md` § tuning pass 1):

| # | Change | Why |
|---|---|---|
| 1 | Tile pop-in layout animation plays on cold create only; removed `grid.scheduleLayoutAnimation()` from `onResume()` | Was replaying the staggered animation on every Home return |
| 2 | `adapter.reload()` (PackageManager query + icon decodes) skipped when the last reload is < 5 min old | Was running synchronously on the UI thread on every Home bounce |
| 3 | Glass-highlight springs: stiffness 260→320, damping ratio 0.58→0.85 | The underdamped spring oscillation dominated frame time |
| 4 | Dock shadows snap to their target instead of animating | Halves the animators per dock move |
| 5 | Ambient glow tint swaps in place instead of a 2-stage ~700 ms alpha animation | Full-screen gradient animating on every dock move |

### 3. Windows tooling + records (new files, not in upstream)
- `install_gathin.ps1` — build-install + enable redirect/screensaver, backs up pre-install settings once
- `restore_gathin.ps1` — full revert (see below)
- `measure_gathin.ps1` / `measure_gathin_v2.ps1` — measurement suites (latency, memory, jank, cold starts)
- `TRIAL-NOTES.md`, `baseline-stock-reverted.txt`, `measure-gathin/` — results + screenshots
- `backup-192.168.29.20.txt` — this stick's pre-install settings (used by restore)

## Measured results (2026-11-09, on-device)

| Metric | Stock Amazon home | This build (tuned) |
|---|---|---|
| App-grid browsing jank (gfxinfo) | 44%, 14 ms p50, 38 ms p90 | **33%, 10 ms p50, 22 ms p90** |
| Dock row jank | — | 73%, 25 ms p50 (rarely scrolled) |
| Netflix cold start, median | 1056 ms | **1008–1083 ms** (at baseline) |
| Idle MemAvailable | ~260 MB | 275 MB, no kswapd0, 0% iowait |
| Launcher idle CPU | — | 0% |
| Home press → launcher | ~2–3 s (no flash) | +0.3–0.7 s after Fire OS's own 2–2.7 s home flash |

Fire OS shows Amazon's home for ~2–2.7 s after the Home key **before any redirect can
fire** — that part is identical on stock and not fixable by any launcher; the launcher's
own cost on top of it is 280–650 ms.

History: an earlier WebView-based custom home (`com.tvbox.home`, separate project)
measured much worse (95% jank / 36 ms, Netflix +70% cold start, swap thrashing) and was
reverted first — the stock baseline above was captured *after* that revert, settled.

## Install (Windows)

```powershell
# Prereqs: JDK 17, Android SDK platform 34 + build-tools 34 (licenses accepted), adb.
cd launcher
gradle.bat assembleDebug
cd ..
pwsh -NoProfile -File .\install_gathin.ps1 -Serial <tv-ip>:5555   # defaults to 192.168.29.20:5555
```

What install does: `adb install -r`, grants `WRITE_SECURE_SETTINGS` (so Menu on the
launcher's Settings button toggles the redirect on the TV, no ADB), enables
`HomeRedirectService`, sets `PhotoDream` as screensaver. It does **not** touch
Amazon's launcher — the redirect just opens over Amazon's home.

## Revert to stock

```powershell
pwsh -NoProfile -File .\restore_gathin.ps1 -Serial 192.168.29.20:5555
```

Restores the original screensaver from `backup-*.txt`, disables the redirect,
uninstalls the launcher, prints verification. Then reboot the stick once to confirm
and turn ADB debugging off in Developer Options.

Manual equivalent:

```sh
adb shell settings put secure enabled_accessibility_services null   # NOT "" — see below
adb shell settings put secure accessibility_enabled 0
adb shell settings put secure screensaver_components com.amazon.ftv.screensaver/.app.services.ScreensaverService
adb uninstall com.gathin.tvhome
```

> **Gotcha (verified on this Fire OS build):** the accessibility-services value must
> be the literal `null`, not an empty string. Fire OS silently restores `""` (and the
> binding) on the next boot; `null` sticks. The same applies when re-enabling: write
> the full component string, never `""`.

To just pause the redirect for a while (keeping the app): press **Menu on the
launcher's Settings button → Use Amazon Home Screen**, or
`adb shell settings put secure enabled_accessibility_services null` and set it back to
`com.gathin.tvhome/com.gathin.tvhome.HomeRedirectService` later.

### 4. Screensaver wallpapers — Indian mix (built, **not yet installed**)
Replaced `saver_01–12.jpg` (screensaver) with 12 freely licensed Indian wallpapers
from Wikimedia Commons (monuments + landscapes: Taj Mahal, Hampi, Hawa Mahal, Golden
Temple, Varanasi ghats, Kerala backwaters, Ladakh, Munnar, Meghalaya, White Rann of
Kutch, Gokarna, Valley of Flowers). Time-of-day `bg_*` backgrounds unchanged.
Attribution: [`CREDITS.md`](CREDITS.md) and [`saver-credits.json`](saver-credits.json).
**APK rebuilt (11.1 MB); not installed on the TV until you confirm.**

## Files added by this fork

| File | Purpose |
|---|---|
| `README-BAM.md` | this summary |
| `TRIAL-NOTES.md` | chronological trial record with all raw numbers |
| `baseline-stock-reverted.txt` | settled stock baseline (the comparison target) |
| `install_gathin.ps1` / `restore_gathin.ps1` | install + full revert |
| `measure_gathin.ps1` / `measure_gathin_v2.ps1` | measurement suites |
| `backup-192.168.29.20.txt` | this stick's pre-install settings |
| `measure-gathin/` | results (`results-live.txt` pre-tune, `results-tuned.txt` post-tune) + screenshots |
| `saver-credits.json` | attribution/licensing metadata for the Indian screensaver wallpapers |
