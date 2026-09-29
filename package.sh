#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
mkdir -p dist
ditto -c -k --norsrc --keepParent 'build/Work Lights.app' dist/Work-Lights-v0.1-macOS.zip
(cd dist && shasum -a 256 Work-Lights-v0.1-macOS.zip > SHA256SUMS)
