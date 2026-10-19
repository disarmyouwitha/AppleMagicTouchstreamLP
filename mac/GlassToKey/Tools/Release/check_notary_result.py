#!/usr/bin/env python3
"""Require Apple's final Accepted status, independently of notarytool's exit code."""
import json
import sys
from pathlib import Path


def check(path):
    try:
        result = json.loads(Path(path).read_text())
        if not isinstance(result, dict):
            raise ValueError('expected an object')
    except (OSError, ValueError) as error:
        print(f'Could not read notarization result: {error}', file=sys.stderr)
        return 1
    status = result.get('status')
    if status != 'Accepted':
        print(f'Notarization status: {status or "missing"}; submission: {result.get("id", "unknown")}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(check(sys.argv[1]))
