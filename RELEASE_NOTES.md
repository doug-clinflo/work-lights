# Work Lights v0.1 — first public preview

A native macOS menu-bar utility that helps keep WiZ lights on while you work quietly.

Create local rooms, assign discovered bulbs, and choose the room you want to control. Pick scene favourites or adjust brightness from the same menu. Everything is configured locally; no account, telemetry, or personal device data is bundled.

Download **Work-Lights-v0.1-macOS.zip** for Apple Silicon or Intel Macs running macOS 13+. Extract it, move Work Lights.app to Applications, and follow the README's first-run setup. **SHA256SUMS** contains the archive checksum.

This is an early preview, ad-hoc signed and not notarised. It restores lights after a motion timeout rather than disabling WiZ motion automation; brief dark intervals remain possible. Rooms are local groups, not imported WiZ-app rooms. Scene support varies by bulb. Multi-room hardware testing and Intel execution need wider validation.

The original activity utility has been used on one real setup. The public release adds offline-tested room isolation and fresh local setup. See the README and TESTING.md for the exact limitations and outstanding checks.
