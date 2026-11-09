# gathin launcher trial — state & decision record

Date: 2026-11-09. Device: Fire TV Stick 4K Max (AFTSSS), Fire OS 7.7.1.7, 192.168.29.20:5555.

## What is installed
- `com.gathin.tvhome` (fire-tv-cleanup launcher, built locally from
  https://github.com/itsmeterrylin/fire-tv-cleanup @ main, Gradle 8.9 / JDK 17)
- Local changes vs upstream: `res/values/config.xml` only —
  dock = Netflix, SmartTube, Hotstar, Amazon Music; Amazon Music un-hidden;
  live_tv_package emptied (com.amazon.tv.livetv is disabled on this stick).
- Home redirect: `HomeRedirectService` accessibility service (same mechanism
  class as the reverted com.tvbox.home, but native app, no WebView).
- Screensaver: `PhotoDream` (was Amazon's
  `com.amazon.ftv.screensaver/.app.services.ScreensaverService` — backed up in
  `backup-192.168.29.20.txt`).
- `WRITE_SECURE_SETTINGS` granted so Menu-on-Settings can toggle the redirect
  on/off from the remote, no ADB needed.

## Why (from the earlier WebView trial, measured)
The com.tvbox.home WebView launcher made the stick measurably slow:
Home bounce 5-6 s (14.5 s worst), 95% janky frames / 36 ms p50, ~120 MB held
while apps ran, Netflix median 1669 ms (vs 979 ms stock), kswapd0 thrashing.
Reverted and verified: stock numbers restored (baseline-stock-reverted.txt).

## Decision rule (agreed with user)
Keep this launcher ONLY if, vs the stock baseline:
- Home latency from an app is acceptable in daily use (target: < 3 s median;
  the mechanism cannot be instant on Fire OS),
- no swap thrashing returns (kswapd0 not in top, iowait ~0),
- Netflix cold start stays within ~15% of 1056 ms,
- launcher jank is dramatically better than the WebView's 95%/36 ms.
Otherwise: restore_gathin.ps1 and stay stock.

## Results (2026-11-09, measured on-device)
| Metric | Stock baseline | WebView (tvbox) | gathin native | Rule |
|---|---|---|---|---|
| Home from app, true latency | ~2-3 s (no flash) | ~4-6 s | **~2.4-3.6 s** (flash + redirect) | target <3 s: BORDERLINE |
| Redirect cost itself | - | seconds (WebView recreate) | **~70 ms + 0.4-0.8 s first frame** | PASS |
| MemAvailable idle | ~260 MB | 96-170 MB | **~305 MB** | PASS (no kswapd0, 0% iow) |
| Netflix cold start median | 1056 ms | 1669 ms | **1108 ms (+5%)** | PASS (<15%) |
| Launcher jank | 44% / 14 ms p50 | 95% / 36 ms | **83% / 31 ms p50** | FAIL (not "dramatically better" than WebView; worse than stock) |

Caveats recorded honestly: poll-based Home latency read 5.5 s but logcat shows ~2.4-3.6 s
(dumpsys polling itself slows the stick; home-latency.sh method is the accurate one).
Jank sample small (42 frames, dock magnification springs); stock test scrolled content.
Memory IMPROVED vs stock - plausibly Amazon's home never fully hydrates when instantly covered.

## Verdict per the agreed rule
MIXED: memory and app speed pass; home latency is at the boundary; jank fails the
"dramatically better" bar. Per the rule this reverts - final call offered to the user
since the trade-off (aesthetics vs ~1 s flash-and-bounce) is a preference.

## Tuning pass 1 (2026-11-09, after "tune jank, then decide")
Local diff vs upstream (all in MainActivity.java, git-revertable):
1. onResume no longer replays the staggered tile pop-in (`grid.scheduleLayoutAnimation()` removed)
   - the pop-in now plays once on cold create only; warm Home returns render immediately.
2. onResume skips the PackageManager scan (labels + per-app icon decode, UI thread) when the
   last reload is < 5 min old (RELOAD_MS). Cold starts still load fresh. This was running on
   every Home bounce.
3. Glass highlight springs: stiffness 260->320, damping 0.58->0.85 (near-critical; kills the
   long underdamped oscillation that dominated frame time on grid moves).
4. Dock shadows now snap to their target scale/position with no animator (halves the animators
   per dock move; shadow waits under the icon's landing spot while the card flies in).
5. Ambient glow color changes swap in place instead of a ~700 ms two-stage alpha animation of
   a full-screen gradient.
6. install_gathin.ps1: no longer clobbers the pre-install backup on re-runs.
Re-measure after rebuild: dock jank, grid jank, Home latency (logcat), Netflix cold, memory.

## Tuning pass 1 results (post-rebuild, on-device)
| Metric | Stock | gathin pre-tune | gathin TUNED |
|---|---|---|---|
| Grid/app browsing jank | 44% / 14 ms p50 / 38 ms p90 | (not measured separately) | **33% / 10 ms p50 / 22 ms p90** |
| Dock row jank | - | 83% / 31 ms p50 | 73% / 25 ms p50 (11-frame sample, weak) |
| Redirect -> gathin first frame | - | 369-828 ms | **280-649 ms** |
| Netflix cold start | 1056 ms | 1108 ms | **1008-1083 ms** |
| MemAvailable idle | ~260 MB | ~305 MB | 275 MB (no kswapd0, 0% iow) |
| Launcher idle CPU | - | 0% | 0% (not in top) |

Grid navigation — the main browsing surface — is now SMOOTHER than stock Amazon home
(33%/10ms vs 44%/14ms). Dock row remains the weakest spot but is rarely scrolled
(4 icons). Home-latency total is dominated by Fire OS's own 2-2.7 s home-appear
time, which no launcher can change (identical on stock).

## Undo (verified reboot-proof for the same setting class on this device)
pwsh -NoProfile -File .\restore_gathin.ps1 -Serial 192.168.29.20:5555
(uses settings put secure enabled_accessibility_services null — NOT "" —
Fire OS resurrects an empty string on boot; restores Amazon screensaver;
uninstalls the app.)

## Files
- install_gathin.ps1 / restore_gathin.ps1 — install + full revert
- measure_gathin.ps1 — measurement suite (same methods as baseline)
- baseline-stock-reverted.txt — the "before" numbers
- measure-gathin\ — results + screenshot
