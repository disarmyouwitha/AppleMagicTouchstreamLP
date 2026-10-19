#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/project.env"
python3 "$ROOT/DriverKitProbe/generate-config.py"
exec xcodebuild -project "$ROOT/$PROJECT_PATH" -scheme "$SCHEME" -configuration Debug -destination 'platform=macOS' -derivedDataPath "$ROOT/build/DerivedData" build "$@"
