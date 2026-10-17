#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec swift test --package-path "$ROOT" --scratch-path "$ROOT/build/SwiftPM" "$@"
