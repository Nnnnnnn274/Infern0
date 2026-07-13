<p align="center">
  <img src="Infern0/Assets.xcassets/AppIcon.appiconset/infern0-icon-master.png" alt="infern0 app icon" width="152">
</p>

<h1 align="center">infern0</h1>

<p align="center">
  A new chapter for the Cyanide project.<br>
  Explore, configure, and run iOS tweaks from one open-source app.
</p>

<p align="center">
  <a href="https://github.com/Nnnnnnn274/Infern0/releases/latest">
    <img alt="Latest release" src="https://img.shields.io/github/v/release/Nnnnnnn274/Infern0?style=flat-square&color=ef4444">
  </a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-111827?style=flat-square">
  <img alt="Version" src="https://img.shields.io/badge/current%20line-2.0-f97316?style=flat-square">
  <a href="LICENSE">
    <img alt="License" src="https://img.shields.io/badge/license-AGPL--3.0-2563eb?style=flat-square">
  </a>
</p>

<p align="center">
  <a href="https://github.com/Nnnnnnn274/Infern0/releases/latest"><strong>Download</strong></a>
  ·
  <a href="https://github.com/Nnnnnnn274/Infern0/issues/new?template=bug_report.yml">Report a bug</a>
  ·
  <a href="https://github.com/Nnnnnnn274/Infern0/issues/new?template=feature_request.yml">Request a feature</a>
  ·
  <a href="https://discord.gg/fx3xvuUyj">Discord</a>
</p>

---

## A fresh start

**infern0** is the active continuation of Cyanide, maintained by
[@Nnnnnnn274](https://github.com/Nnnnnnn274). The goal is simple: preserve the
research and creativity behind the original project, finish its incomplete
ideas, and build a cleaner and more dependable tweak-running experience.

This is not a traditional jailbreak. infern0 uses the DarkSword kernel
read/write foundation and RemoteCall to apply supported changes from a
sideloaded app. Many visual tweaks live only for the active session; a smaller
set intentionally modifies persistent files and is clearly marked in the app.

> [!IMPORTANT]
> infern0 is experimental system software. A tweak can crash SpringBoard,
> disturb the Home Screen layout, partially apply, or stop working after an iOS
> update. Read each package warning, keep backups, and test responsibly.

## What we are building

| Area | Highlights |
| --- | --- |
| **Home Screen** | SBCustomizer, Gravity Lite, Cylinder Lite, Rounded Icons, Watch Layout, labels, badges, themes, and layout controls |
| **Status Bar** | StatBar, NSBar, NiceBar Lite, Signal Readouts, carrier text, and live system information |
| **Control Center** | Layout, spacing, appearance, status, haptics, and security experiments |
| **Theming** | Cyanide Themer, SnowBoard Lite imports, icon styles, and LiveWP |
| **System tools** | Powercuff, OTA controls, Watch pairing overrides, location simulation, IPA tools, and carefully labeled persistent changes |
| **Extensibility** | QuickLoader for local JavaScript tweaks and source repositories for installable community tweaks |

### New Home Screen work

- **Rounded Icons** applies smooth, configurable corners to every discovered
  Home Screen icon without requiring a theme.
- **Watch Layout** creates a compact Apple Watch-style grid with circular,
  pressable icons and reversible layout changes.
- **Gravity Lite** runs physics on live icon views across discovered pages so
  icons remain interactive.
- **Cylinder Lite** applies perspective depth across the Home Screen while
  preserving normal icon taps.
- **Barmoji** now presents real pressable emoji buttons with highlight and
  selection feedback. Its enabled preference survives reboot and the overlay is
  recreated with the next infern0 SpringBoard session. Cross-process text
  insertion into arbitrary app keyboards is still a work in progress.

## Project status

infern0 2.0 is an active reboot, not a promise that every experiment is
finished. Work is currently focused on:

- making existing tweaks configurable and easier to restore;
- keeping icons and controls interactive after visual transformations;
- applying Home Screen tweaks consistently across all discovered pages;
- producing useful activity logs for setup, apply, refresh, and cleanup;
- finishing older Cyanide experiments without hiding their limitations;
- improving exploit and RemoteCall reliability across supported targets.

The AMFI, CoreTrust, and kPAC paths remain research-heavy and may be incomplete
or unreliable on some devices. Their presence in the source tree should not be
read as a universal compatibility guarantee.

## Compatibility

The app currently gates tweak execution to:

- iOS/iPadOS **17.0 through 18.7.1**
- iOS/iPadOS **26.0 through 26.0.1**

The kernel issues used by this project, <code>CVE-2025-43510</code> and
<code>CVE-2025-43520</code>, were fixed in iOS/iPadOS 18.7.2 and 26.1. Later
releases are outside the current exploit window. A19 and M5 devices are not
supported.

Compatibility inside those ranges can still vary by device and tweak. Check
the package description and activity log before assuming a feature is safe for
your setup.

## Install

1. Open the [latest release](https://github.com/Nnnnnnn274/Infern0/releases/latest).
2. Download the current <code>.ipa</code>.
3. Install it with a normal IPA sideloading or signing tool.
4. Launch infern0, review the compatibility warning, and configure tweaks before
   adding them to the queue.

Do **not** run infern0 through LiveContainer. The exploit and process behavior
expect a normally installed application.

## How tweak state works

infern0 deliberately separates different kinds of changes:

- **Live session tweaks** run through RemoteCall and generally need infern0's
  SpringBoard session to remain active. A respring restores stock behavior.
- **Saved preferences** survive app relaunches and reboots, then control what
  infern0 recreates during a later session.
- **Persistent changes** write system-accessible files and remain until their
  documented restore action is used. These packages carry stronger warnings.

The Settings screen exposes per-tweak controls, current intent/applied state,
cleanup behavior, and a detailed activity log. If something behaves
unexpectedly, save that log before restarting the app.

## Build from source

Requirements:

- macOS with a compatible Xcode and iPhoneOS SDK;
- command-line build tools;
- <code>xcbeautify</code> is optional—the build script falls back to raw
  <code>xcodebuild</code> output.

Build an unsigned IPA:

~~~sh
./scripts/build.sh
~~~

The default build uses the <code>Infern0</code> scheme and writes:

~~~text
build/Infern0.ipa
~~~

Equivalent manual build:

~~~sh
xcodebuild \
  -project Infern0.xcodeproj \
  -scheme Infern0 \
  -sdk iphoneos \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
~~~

Release notes for completed and upcoming work live in
[RELEASE_NOTES.md](RELEASE_NOTES.md).

## Contributing

Bug reports, test results, documentation fixes, and focused tweak improvements
are welcome.

Before opening an issue:

1. confirm that the device and OS are in the supported range;
2. reproduce with as few enabled tweaks as possible;
3. restore the affected tweak and try once more;
4. attach the infern0 activity log and exact device/iOS information;
5. explain whether the problem happens on Apply, refresh, cleanup, respring, or
   reboot.

Use the repository templates to
[report a bug](https://github.com/Nnnnnnn274/Infern0/issues/new?template=bug_report.yml)
or
[propose a feature](https://github.com/Nnnnnnn274/Infern0/issues/new?template=feature_request.yml).

## Community

- [Discord](https://discord.gg/fx3xvuUyj)
- [Signal support and testing group](https://signal.group/#CjQKIP0pxjc9V52ddCNk--04DosuoQl-vVOsznJfQ4GwlrlxEhCveFhBS8YdNcILpUFt7IqC)
- [GitHub issues](https://github.com/Nnnnnnn274/Infern0/issues)

## Project lineage and credits

infern0 stands on substantial work from the iOS research and tweak communities:

- [zeroxjf](https://github.com/zeroxjf) created Cyanide and its
  Installer/Settings direction.
- [opa334](https://github.com/opa334) created
  [darksword-kexploit](https://github.com/opa334/darksword-kexploit), ChOma,
  and XPF.
- [wh1te4ever](https://github.com/wh1te4ever) created
  [darksword-kexploit-fun](https://github.com/wh1te4ever/darksword-kexploit-fun)
  and the RemoteCall foundation used by this project.
- [rooootdev](https://github.com/rooootdev) contributed exploit behavior used
  while stabilizing the fork.
- [kolbicz](https://github.com/kolbicz) contributed DarkSword tweaks, OTA work,
  and the original RemoteCall location-simulation prototype.
- [rpetrich](https://github.com/rpetrich) created Powercuff.
- [Julio Verne](https://github.com/julioverne) created the original Gravity
  tweak.
- [d1y](https://github.com/d1y) published the AGPL-3.0
  [cyanide-ios](https://github.com/d1y/cyanide-ios) sources adapted by several
  ports in this tree.
- [tomt000](https://github.com/tomt000) created Dynamic Stage, whose
  scene-hosting design inspired Dynamic Stage Lite.
- <code>ezzuldinSt</code>, <code>YangJiiii</code>,
  <code>@Little_34306</code>, <code>neonmodder123</code>, and the many testers
  and contributors credited in package descriptions helped shape individual
  tools and ports.

The interface also takes inspiration from classic
[Installer.app](https://github.com/AppTapp/Installer-3) and
[Sileo](https://github.com/Sileo/Sileo).

## License

infern0 is distributed under the
[GNU Affero General Public License v3.0](LICENSE).

Fork it, study it, improve it, and keep covered changes open under the same
license. This project is provided without warranty.

---

<p align="center">
  <strong>infern0 is where Cyanide continues—cleaner, more open, and moving forward.</strong>
</p>
