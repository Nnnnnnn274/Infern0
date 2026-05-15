# Cyanide

An iOS tweak runner built on top of the DarkSword kernel r/w primitive.

Fork of [`wh1te4ever/darksword-kexploit-fun`](https://github.com/wh1te4ever/darksword-kexploit-fun)
for iOS kernel research. This app wraps the native DarkSword kernel stages in
an Objective-C iOS app and adds a few reliability fixes for repeated local
testing. It does not ship the browser-delivered WebKit/dyld parts of the
original DarkSword chain.

## Supported Targets

Tested target range:

- iOS/iPadOS 17.0 through 18.7.1
- iOS/iPadOS 26.0 through 26.0.1
- A19/M5 devices are not supported

The kernel bugs used here, `CVE-2025-43510` and `CVE-2025-43520`, were fixed in
iOS/iPadOS 18.7.2 and 26.1. Later builds are outside this kernel exploit window.

## What This Fork Changes

- Cleans shared exploit state before each attempt.
- Matches the target process with an explicit marker.
- Validates sockets before using the spray path.
- Treats missed races as retryable failures instead of hard failures.
- Tightens the A18/M4 `pe_v2` path with initialized target-file contents,
  stable local remap addresses, bounded page freeing, socket-spray preflight
  checks, and controlled zone-trim retries.

## Kernel Research Features

- Escape the app sandbox.
- Control or crash userspace processes from the app.
- Change UID, GID, and sticky bits on target files.
- Disable ASLR by setting `P_DISABLE_ASLR` in `launchd`'s `proc->p_flag`.

## Tweaks

These tweaks have only been tested on iOS 18.x. Expect version drift in
SpringBoard and related daemons to break things on other releases.

- **SBCustomizer**: dock icon count, home-screen columns/rows, and hidden icon
  labels. This ports the lightsaber sbcustomizer payload to native remote-call.
- **SpringBoard Tweaks**: disable App Library, disable icon fly-in animation,
  zero wake animation, zero backlight fade, and double-tap to lock. Ported from
  [`kolbicz/DarkSword-Tweaks`](https://github.com/kolbicz/DarkSword-Tweaks).
- **Powercuff**: CPU/GPU underclocking through simulated `thermalmonitord`
  pressure levels: off, nominal, light, moderate, and heavy. The setting lasts
  until reboot. Port of [`rpetrich/Powercuff`](https://github.com/rpetrich/Powercuff).
- **StatBar**: battery temperature and free-RAM overlay anchored to the
  SpringBoard status bar, with optional C/F and network-speed display.
- **OTA Disabler**: toggles the launchd OTA `disabled.plist` to block or
  unblock update prompts. Ported from
  [`kolbicz/DarkSword-Tweaks`](https://github.com/kolbicz/DarkSword-Tweaks).
- **Respring**: in-app WKWebView trigger for restarting SpringBoard.

## Credits

- [`rooootdev`](https://github.com/rooootdev): working kexploit behavior used to stabilize this fork.
- [`neonmodder123`](https://github.com/neonmodder123): Web Respring method.
- [`kolbicz`](https://github.com/kolbicz): OTA Disabler and SpringBoard tweaks.
- [`rpetrich`](https://github.com/rpetrich): Powercuff.

## Build

```sh
./scripts/build.sh
```

The build script uses the `Cyanide` scheme, disables code signing, and writes
an unsigned IPA to:

```text
build/Cyanide.ipa
```

Equivalent manual build:

```sh
xcodebuild \
  -project Cyanide.xcodeproj \
  -scheme Cyanide \
  -sdk iphoneos \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```
