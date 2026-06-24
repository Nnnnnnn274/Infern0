# Release Notes

Keep concrete, user-facing release bullets here as changes land. The release
script reads `## Pending` before building, uses those bullets for GitHub release
notes and the generated in-app changelog, then moves them under `## Released`
after a successful build.

Good bullets describe the behavior users will notice:

- Reduced flicker when Dynamic Stage windows resize.
- Fixed installer queue badges after changing package selection.
- Added an iOS 17 fallback for Disable App Library.

Use one bullet per user-facing tweak or fix. Do not combine unrelated tweak
changes into the same bullet.

Avoid vague bullets like "Update settings", "Change project files", or
"Misc fixes".

It is OK to mention user-visible experimental or patron-gated tweaks when
describing added or improved features. When announcing a new experimental
feature, say it is available to Patrons for early access and credit original
tweak or project authors alongside the Cyanide port author when known. Do not
mention private submodule activity, internal/private source movement, private
repository names, private implementation details, or commentary about which
experimental pieces are working versus not wired. If the change cannot be
phrased as a user-facing feature or fix without revealing private activity,
omit it.

## Pending


## Released

### v1.3.4 - 2026-06-24

- [x] Fixed the queue popup staying visible after Apply Tweaks completes.

### v1.3.3 - 2026-06-24

- [x] Repo tweak detail view now shows the actual tweak description instead of generic install text.
- [x] Cleaned up tweak detail view styling — larger, more readable description and info text.
- [x] Source refresh on update forces repo cache repopulation so per-tweak icons and authors appear immediately.
- [x] Package icon badges now cycle through a spectrum of colors across all list views.

### v1.3.2 - 2026-06-24

- [x] Redesigned Home, Packages, and Sources tabs with a unified visual style — gradient hero, colored icon badges, bold section headers, and compact list cells.
- [x] Packages tab now shows a Recently Added section for new source tweaks and a flat alphabetical package list; category browser moved to Sources.
- [x] Added per-tweak SF Symbol icons and per-tweak author to the repo JSON format.
- [x] Added pull-to-refresh on Packages and Sources, with a green success banner after refresh.
- [x] QuickLoader opened from Home or Sources now runs tweaks directly without going through the install queue.
- [x] Fixed repo tweaks showing both QuickLoader and the tweak itself in the queue and installed package lists.
- [x] Updated JS tweak repo documentation with the new symbol and author optional fields.

### v1.3.1 - 2026-06-24

- [x] Improved QuickLoader UI with loaded tweak display, active status indicator, clear button, and prominent activate button.
- [x] Made the install queue show the loaded QuickLoader script name instead of a generic label.
- [x] Restored Hide Home Bar's stable page-zero path, forced cache-busted repo script fetches before QuickLoader installs, and prompts for respring after repo-served Hide Home Bar runs.
- [x] Fixed Location Simulator coordinate entry for Chinese labels, directions, and full-width punctuation.
- [x] Fixed SnowBoard Lite only applying some visible icons on iOS 26.
- [x] Improved SnowBoard Lite live repair by reusing the SpringBoard channel between ticks and backing off background repair work that could make SpringBoard feel slow.
- [x] Blocked SnowBoard Lite activation until a theme is selected, with a shortcut to open theme settings.
- [x] Made Hide Home Bar stay registered as hidden after respring, with Restore shown as the next package action.

### v1.2.23 - 2026-06-23

- [x] Added a Home tab with What's New, JavaScript Tweaks and RemoteCall Tweaks overviews, and community links.
- [x] Redesigned Packages as a category browser — tap a category to see its tweaks.
- [x] Added JavaScript tweak support by @MinePlayer16: QuickLoader for local .js files and an online Sources tab for HTTPS repos, with the zeroxjf repo (including Hide Dock) pre-installed.
- [x] Added developer documentation in the Sources tab for writing JS tweaks and setting up a repo, with copy and share options.
- [x] Added automatic source refresh with update detection badges on the Sources tab.
- [x] Fixed JS runner stalls, SBCustomizer queue/apply issues, SnowBoard Lite respring delays, and kernel setup hangs on IOSurface mapping failures. Not all reported bugs are addressed yet, but this update should bring more stability overall.

### v1.2.22 - 2026-06-12

- [x] Made FastLockX Lite install through the normal Apply Tweaks queue so it uses the shared SpringBoard setup with other runtime tweaks.
- [x] Paused FastLockX Lite retry pulses while the device is unlocked.
- [x] Improved Hide Home Bar page zeroing stability with a DirtyZero-style single-page write path and verified fallback.
- [x] Improved kernel setup stability when preparing the memory-racing stage.
- [x] Improved FastLockX Lite compatibility with Dynamic Stage Lite by finishing FastLockX setup before Dynamic Stage starts its live control loop.
- [x] Fixed FastLockX Lite not resuming its retry pulse after the device locks on iOS 18.
- [x] Prevented Dynamic Stage Lite from background-filling App Library tiles while FastLockX Lite is active to avoid SpringBoard restarts.
- [x] Fixed Dynamic Stage Lite windows being torn down when the device locks or the screen sleeps.
- [x] Improved FastLockX Lite unlock reliability by debouncing lock-screen timer sync and using no-wake unlock nudges when Face ID leaves the lock screen awake.

### v1.2.21 - 2026-06-12

- [x] Split SnowBoard Lite import into separate Folder and Archive (ZIP/DEB) options so archive imports work reliably on all sideloaded installs.
- [x] Added a hint in the folder import dialog for sideloaded users whose signing tool needs "Match provisioning identifier" enabled.

### v1.2.20 - 2026-06-12

- [x] Fixed SBCustomizer showing as still queued after a successful icon-label or layout apply.
- [x] Fixed unsupported-version runs leaving the Activity sheet stuck in a running state.
- [x] Fixed local builds failing on macOS Bash when no simulator-only xcodebuild extras are set.
- [x] Fixed SnowBoard Lite imports on Signulous installs by copying selected themes into Cyanide instead of opening them in place.

### v1.2.19 - 2026-06-11

- [x] Added FastLockX Lite, available to Patrons for early access, as an experimental tool that automatically unlocks the screen once Face ID is accepted; tested on iOS 18 and iOS 26, with iOS 17 support not confirmed yet. Credits: original FastLockX author Artem Kasper and Cyanide port by zeroxjf.
- [x] Fixed a Patreon linking crash when returning from the in-app OAuth flow.

### v1.2.18 - 2026-06-11

- [x] Tightened Hide Home Bar standalone queue enforcement across all package actions.
- [x] Added iOS 17 support for Drag Coefficient and lowered its minimum value to 0.01.
- [x] Replaced Home Layout Extras sliders with exact number entry rows.

### v1.2.17 - 2026-06-09

- [x] Added Hide Home Bar as a beta package using DirtyZero-style MaterialKit page zeroing.
- [x] Made Hide Home Bar run as a standalone queue item with prominent install-queue guidance.
- [x] Added public Hide Home Bar credits in the package details.
- [x] Added a respring prompt after Hide Home Bar finishes so users know when the home indicator will disappear.
- [x] Fixed a queue review crash when pending changes finish while the queue screen is refreshing.
- [x] Reduced Dynamic Stage Lite picker startup work to avoid SpringBoard resprings on large app libraries.

### v1.2.16 - 2026-06-09

- [x] Prevented overlapping tweak actions from interfering with Apply Tweaks and direct controls.
- [x] Fixed Dynamic Stage Lite sidebar interference with the main tweak UI.

### v1.2.15 - 2026-06-09

- [x] Fixed Double Tap to Lock triggering while entering a Lock Screen passcode.
- [x] Added App Switcher Grid as a Beta tweak.
- [x] Replaced the installer contact button with Signal group and GitHub Issues links.
- [x] Removed the standalone Cyanide Themer listing in favor of SnowBoard Lite.
- [x] Let active Location Simulator target changes use parked kernel recovery before refreshing.
- [x] Kept OTA Block behind kernel recovery before editing launchd job state.
- [x] Kept Call Recording Sound behind kernel recovery before writing CallServices files.
- [x] Kept Watch Pairing override behind kernel recovery before writing NanoRegistry files.

### v1.2.14 - 2026-06-09

- [x] Fixed Dynamic Stage Lite visibility for paid users.
- [x] Fixed LiveWP video selection from Files and added Photos video selection.
- [x] Let active LiveWP users change videos from the installer without deactivating the wallpaper first.
- [x] Prevented LiveWP activation until a valid video has been selected.

### v1.2.13 - 2026-06-08

- [x] Moved Location Simulator to Beta and into the public app tree so it is available without enabling Experimental Tweaks.
- [x] Moved Call Recording Sound to Beta and into the public app tree so it is available without enabling Experimental Tweaks.

### v1.2.12 - 2026-06-08

- [x] Fixed Location Simulator exact coordinate entry so pasted decimal pairs and compass-suffix coordinates are normalized correctly.

### v1.2.11 - 2026-06-07

- [x] Added an optional simulator build path that uses a simulator XPF dylib without changing the normal device IPA build.
- [x] Added a StatBar option to show only live network upload and download speed.
- [x] Fixed the installer queue popup crash on iPadOS when the tab bar is attached after launch.
- [x] Fixed StatBar landscape placement on iPad by sizing the overlay from SpringBoard's active window bounds.
- [x] Fixed custom theme bundle-ID PNGs not preloading for apps that are only visible inside folders.
- [x] Prevented Dynamic Stage Lite and Cyanide Themer live icon repair from running together to avoid SpringBoard resprings.

### v1.2.10 - 2026-06-05

- [x] Updated the Cyanide Signal group invite link.

### v1.2.9 - 2026-06-05

- [x] Fixed NiceBar Lite weather slots by restoring the location-based weather picker, cache, and live refresh flow.

### v1.2.8 - 2026-06-05

- [x] Fixed LiveWP disappearing after leaving Cyanide and aligned NSBar/NiceBar Lite refresh loops with screen wake and sleep state.

### v1.2.7 - 2026-06-05

- [x] Fixed the Installer queue popup overlapping the bottom tab bar on iOS 18.

### v1.2.6 - 2026-06-05

- [x] Fixed LiveWP video changes stopping after one run and SnowBoard Lite icon themes drawing over rounded icon corners.

### v1.2.5 - 2026-06-05

- [x] Replaced the first-launch log collection notice with a Cyanide Signal group invite for feedback, feature requests, and support.
- [x] Added NSBar, NiceBar Lite, SnowBoard Lite, and LiveWP ports from d1y/cyanide-ios, with Settings controls and Installer package credits.
- [x] Allowed public Cyanide checkouts to build without the private experimental tweak submodule.

### v1.2.4 - 2026-06-03

- [x] Added a StatBar refresh-rate setting and reduced battery use from repeated temperature polling.
- [x] Fixed Installer queue edge cases so no-op applies finish cleanly and pending activations are remembered after reopening Cyanide.

### v1.2.3 - 2026-06-03

- [x] Improved Gravity Lite startup on iOS 17 by using the faster live-icon capture path.
- [x] Fixed a recent tweak startup regression that could hang while opening the SpringBoard injection channel on A16+ iPhones.
- [x] Fixed Installer package state so successfully applied SpringBoard tweaks no longer appear stuck as activation pending.

### v1.2.2 - 2026-06-03

- [x] Fixed kernel panic on A16+/M-series iPads by guarding the t1sz_boot override so the PAC mask uses the correct value.

### v1.2.1 - 2026-06-03

- [x] Added Drag Coefficient tweak — custom SpringBoard animation speed multiplier ported from kolbicz/DarkSword-Tweaks, with a 5–200% slider (50% = 2× faster, 100% = stock).

### v1.2.0 - 2026-06-03

- [x] Added Gravity Lite with home screen and dock icon physics, tilt control, widget support, and iOS 18/26 compatibility.
- [x] Polished installer, settings, and log presentation with clearer status text, cleaner startup branding, and a maintained release-notes workflow.
- [x] Improved tweak activation and cleanup so unchanged tweaks are not reapplied unnecessarily and SpringBoard-backed tweaks deactivate more reliably.

### v1.1.22 - 2026-06-02

- [x] Reduced flicker when Dynamic Stage windows resize by staging new scene hosts and retiring old hosts after the remote layer has populated.
- [x] Added stronger transition shielding around Dynamic Stage app open, close, and apply paths.
- [x] Tracked DarkSword toggle apply results independently in Settings.
- [x] Improved Disable App Library handling with an iOS 17 fallback path.
- [x] Refined installer queue, badges, and activity status UI.
- [x] Tightened Log tab typography for dense verbose traces.
- [x] Updated the release script to capture dirty submodule changes before committing and tagging the parent release.
