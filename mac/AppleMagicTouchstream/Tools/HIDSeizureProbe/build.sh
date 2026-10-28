#!/bin/bash
set -euo pipefail
PROBE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$PROBE_ROOT/build.py" "$@"
