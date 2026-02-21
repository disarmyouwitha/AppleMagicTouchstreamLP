#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

mapfile -t transcript_files < <(find ReplayFixtures -maxdepth 1 -type f -name "*.transcript.jsonl" | sort)

if [[ "${#transcript_files[@]}" -eq 0 ]]; then
  echo "No replay transcript baselines found in ReplayFixtures/."
  exit 1
fi

non_engine_files=()
for transcript in "${transcript_files[@]}"; do
  if [[ "$transcript" != *.engine.transcript.jsonl ]]; then
    non_engine_files+=("$transcript")
  fi
done

if [[ "${#non_engine_files[@]}" -gt 0 ]]; then
  echo "Non-canonical transcript baseline names detected:"
  for file in "${non_engine_files[@]}"; do
    echo "  - $file"
  done
  echo "Only '*.engine.transcript.jsonl' baselines are allowed."
  exit 1
fi

for transcript in "${transcript_files[@]}"; do
  fixture="${transcript%.engine.transcript.jsonl}.jsonl"
  if [[ ! -f "$fixture" ]]; then
    echo "Missing fixture for transcript baseline: $transcript"
    echo "Expected fixture path: $fixture"
    exit 1
  fi

  swift run --disable-sandbox ReplayHarness \
    --fixture "$fixture" \
    --expected-transcript "$transcript" >/dev/null
done

echo "Replay baseline verification passed (${#transcript_files[@]} baseline(s))."
