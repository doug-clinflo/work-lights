# Testing

## Automated, offline

Run `bash scripts/build.sh`. Both architectures are compiled; the host architecture executes the tests. No LAN traffic or settings writes occur in self-test mode.

Covered: only selected-room targets are returned; other-room lights are excluded from restoration; fresh setup is empty and paused; configuration round-trips; duplicate identities are rejected; only verified off bulbs can be restored; inactive/already-on/wrong-identity/wrong-address cases are suppressed; malformed replies are ignored; dimming clamps to 10–100; absent brightness is not guessed; scene and brightness fields remain separate; confirmations must match observed state.

## Manual release checklist (not yet completed for v0.1)

- Fresh user account: empty local configuration, paused app, no automatic adoption.
- Create two rooms, enrol different bulbs, rename/move/forget/delete. Quit/relaunch and verify persistence.
- Select room A: automatic restoration, scene and dimming commands must leave room B unchanged. Switch and repeat.
- Quit after corrupting a disposable test configuration, relaunch, and verify no control or destructive overwrite.
- Check an already-on light is not reset. Check a motion timeout restores only selected-room lights.
- Test Pause, idle beyond 15 minutes, one-hour hold, screen lock, sleep/wake and user switching.
- Reassign a bulb's DHCP lease, rediscover, and verify identity and room are retained.
- Disconnect networking and test backoff/recovery. Deny local-network access, then grant it in macOS settings.
- Test unsupported scenes, mixed brightness, 10%/100% bounds, offline bulbs and partial confirmations.
- Verify optional login start on next login, then disable it and verify it stays disabled.
- Test downloaded app/Gatekeeper flow and actual execution on both Intel and Apple Silicon.

Report failures without personal IP addresses, MAC identities or settings files.
