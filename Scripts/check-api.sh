#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mode=check
case "${1:-}" in
  "") ;;
  --update) mode=update ;;
  *)
    echo "usage: Scripts/check-api.sh [--update]" >&2
    exit 2
    ;;
esac

rm -rf .build/out/symbolgraph
output="$(swift package dump-symbol-graph \
  --skip-synthesized-members \
  --minimum-access-level public 2>&1)"
printf '%s\n' "$output"
graph_directory="$(printf '%s\n' "$output" | sed -n 's/^Files written to //p' | tail -1)"
if [[ -z "$graph_directory" || ! -d "$graph_directory" ]]; then
  echo "could not locate SwiftPM's symbol-graph output directory" >&2
  exit 1
fi

python3 Scripts/api-baseline.py \
  "$mode" \
  "$graph_directory" \
  Documentation/API/TermLoom.json
