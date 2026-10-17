#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE="$ROOT/OpenMultitouchSupportXCF.xcframework.zip"
[[ -f "$ARCHIVE" ]] || { echo "Run $ROOT/build_framework.sh --release first." >&2; exit 1; }
swift package compute-checksum "$ARCHIVE"
