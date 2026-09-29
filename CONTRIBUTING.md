# Contributing

Open an issue describing the problem and expected behaviour before a large change. Small pull requests with a focused explanation are welcome.

Run `bash scripts/build.sh` and include relevant manual checks from TESTING.md. Preserve the explicit macOS deployment target and room isolation. Keep local network traffic minimal; do not automatically enrol newly discovered devices or overwrite invalid user configuration.

Do not commit app bundles, local settings, home-network addresses, device identities, credentials, or private logs. Synthetic protocol fixtures should use documentation IP ranges and invented identities. Builds belong in release assets, not Git history.
