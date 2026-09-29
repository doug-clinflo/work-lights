# 💡 Work Lights

**Keep your WiZ lights on while you work quietly at your Mac.**

A small native macOS menu-bar utility with local rooms, activity-aware lighting, scene favourites and brightness controls. No account, cloud service, AI loop or Python runtime required.

**v0.1 — early preview.** Built for macOS 13 or later, with Apple Silicon and Intel binaries. The original single-room utility has been used on one real setup; the public room workflow needs wider hardware testing. Not affiliated with WiZ or Signify.

## Your room. Your mood.

- **Rooms:** create local groups such as Office or Studio, assign discovered bulbs, and select the room you are working in.
- **Activity:** maintain the selected room's lights while using the keyboard or mouse, with a 15-minute idle grace period.
- **Quiet working:** choose Keep on for 1 hour for reading or calls. Sleep/session changes cancel the hold.
- **Scenes:** Deep work, Fresh start, Coffee break, Golden hour, Ocean drift, Fireside, Wind down and Candlelit.
- **Brightness:** dim or brighten each light by 10 percentage points, or set the selected room to 10%, 30%, 50%, 75% or 100%.
- **Control:** persistent Pause, optional start at login, and confirmation of manual changes.

## Install and set up

1. Download the macOS ZIP from this repository's Releases page, extract it, and move **Work Lights.app** to Applications.
2. Open the app and allow local-network access if macOS requests it. This preview is ad-hoc signed, **not Developer ID signed or notarised**. macOS may require its normal Open Anyway procedure; only do this if you trust the source. Building from source is also supported.
3. Open the 💡 menu, choose **Room → New room**, and name it.
4. Choose **Check addresses / discover**. Under **Add discovered lights to [room]**, select the bulbs belonging to that room. Addresses and MAC identities are shown; use the WiZ app/router to identify bulbs. There is no automatic room import or bulb identification blink yet.
5. Repeat for other rooms. **Manage assigned lights** lets you move a bulb between rooms or forget it. One bulb belongs to at most one room.
6. Select the room to control, then choose **Resume automatic control**. The app starts paused on a fresh installation and never adopts discovered bulbs automatically.
7. Optionally select **Enable start at login**, after placing the app in its permanent location. This takes effect at the next login.

If upgrading from a private prototype, disable its start-at-login entry and quit it first. The public release has its own app identity and local settings. Create your rooms afresh so two controllers do not compete. Version v0.1 starts the public release series independently of prototype numbering.

## What “room” means

Rooms are **local groups in Work Lights**, not WiZ account rooms. They neither import nor modify WiZ-app room assignments. The selected room is the target for automatic keep-on, scenes and brightness. Other rooms receive no lighting commands. Discovery may query all WiZ bulbs visible on the local network.

Switching rooms moves automatic control to the new room and cancels any timed hold. It does not turn the old room off; existing WiZ automation remains in charge there. Deleting a room unassigns its lights and pauses automatic control. Unassigned lights remain manageable but are not controlled.

## How it works

The app reads elapsed macOS input inactivity, checks session/sleep state, and queries selected lights approximately every 15 seconds during active use. It sends ON only when an assigned bulb reports OFF, with a 30-second per-bulb cooldown. Already-on lights are not repeatedly sent ON commands. It does not continually reapply scenes or brightness.

Startup and periodic discovery query the local network. Saved MAC identities are used to update changed IP addresses. Unknown lights remain candidates until explicitly assigned. Missing bulbs remain saved; when all selected lights are unreachable, polling backs off to a maximum five-minute interval. Discovery is attempted every five minutes during active control and can be requested manually, including while paused.

Manual controls recheck bulb identity and state, skip changes already satisfied, and read state afterward. Feedback distinguishes confirmed changes, unchanged/skipped bulbs, offline bulbs and unconfirmed results. Manual controls turn lights on and work while automatic control is paused, without unpausing it.

## Limitations — please read

- **Restoration, not motion-system override.** WiZ may turn lights off first; Work Lights typically restores them within the next 15-second check. Failures and cooldowns can make this longer. It cannot promise uninterrupted light.
- **Intentional OFF looks like a motion timeout.** Pause automatic control before deliberately switching the room off.
- **Input is not presence.** Quiet reading or calls can exceed the 15-minute grace period. Use the timed hold. Synthetic input can also affect the macOS idle counter. No camera-based presence detection is used.
- **Sleep and lock stop intervention.** The app never sends OFF. Existing WiZ automation decides when lights go out. Lock detection uses macOS session information; test it on your OS release.
- **Local network required.** Mac and bulbs must have reachable local UDP connectivity. Guest networks, VLAN isolation, VPNs, firewalls, or local-network permission denial can prevent discovery/control. Broadcast getPilot support can vary by firmware. There is no subnet scanner, cloud fallback or manual IP entry in this preview.
- **Scenes depend on bulb model.** Colour scenes are not available on every bulb. A scene may set its own brightness; turning a bulb back on may restore dynamic effects differently by firmware. Brightness commands omit scene parameters, but firmware decides the visual result.
- **One selected room at a time.** No schedules, per-room idle limits, WiZ room sync, multi-Mac coordination, automatic updater, or remote control.
- **Early testing.** Offline logic tests cover room targeting, persistence, validation, brightness bounds and restoration decisions. GUI flows, real multi-room behaviour, Intel execution, DHCP changes and OS permissions need broader testing. A successful UDP send alone is not proof a bulb changed state.

## Privacy and local data

No telemetry, accounts, cloud requests, typed-text collection or personal configuration is included in the repository or release archive. The app reads time since input, not keystroke contents. It discovers local devices and sends WiZ UDP messages on port 38899.

At first launch it creates:

- `~/Library/Application Support/WorkLightsCommunity/configuration.json`: your room names, selected room, Pause preference, assigned bulb MAC identities and last-known IP addresses.
- If enabled, `~/Library/LaunchAgents/org.worklights.app.plist`: the per-user login entry, containing the app's local executable path.

These files are created locally, not committed or uploaded. **Open local settings folder** reveals the settings. Invalid settings disable control rather than being silently overwritten. MAC matching prevents accidental adoption, but is not cryptographic authentication: use this on a trusted LAN.

## Build and test

Requires macOS and Apple's Xcode Command Line Tools with a Swift compiler supporting macOS 13 targets. No third-party runtime packages are used.

```sh
bash scripts/build.sh
bash scripts/package.sh
```

The build explicitly targets macOS 13, produces a universal `build/Work Lights.app`, ad-hoc signs it, verifies the signature and runs offline self-tests. Packaging creates `dist/Work-Lights-v0.1-macOS.zip` and `dist/SHA256SUMS`. GitHub Actions repeats this workflow on macOS; its first remote run must still be verified after publishing. Builds are repeatable from source, not promised byte-for-byte reproducible.

See [TESTING.md](TESTING.md) for a real-device test checklist. Please include macOS version, Mac architecture and bulb model/firmware in issues. Do not attach your settings file, home-network addresses, or full device identities.

## Uninstall

Choose **Disable start at login**, then **Quit**, and delete the app. Optionally remove the local settings directory above. Your WiZ room setup and motion automation are unchanged.

## Contributing and licence

Small, focused fixes and reports from different WiZ setups are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). MIT licensed; see [LICENSE](LICENSE).

Protocol and scene references: [pywizlight](https://github.com/sbidy/pywizlight) and its [scene catalogue](https://github.com/sbidy/pywizlight/blob/master/pywizlight/scenes.py). This app is an independent Swift implementation and does not bundle that library.
