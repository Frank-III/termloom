#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
workspace="$(dirname "$root")"
skip_herdr=false
skip_codex=false
skip_motel=false

for argument in "$@"; do
  case "$argument" in
    --skip-herdr) skip_herdr=true ;;
    --skip-codex) skip_codex=true ;;
    --skip-motel) skip_motel=true ;;
    *)
      echo "usage: Scripts/test-consumers.sh [--skip-codex] [--skip-herdr] [--skip-motel]" >&2
      exit 2
      ;;
  esac
done

run_package_checks() {
  local label="$1"
  local path="$2"
  printf '\n== %s ==\n' "$label"
  (
    cd "$path"
    swift format lint --strict --recursive Package.swift Sources Tests
    swift test
  )
}

printf '\n== Ratatui public API ==\n'
"$root/Scripts/check-api.sh"

run_package_checks "Ratatui core" "$root"

printf '\n== Ratatui ecosystem ==\n'
"$root/Scripts/test-ecosystem.sh"

codex_path="${RATATUI_CODEX_PATH:-$workspace/codex-swift}"
if ! $skip_codex; then
  if [[ -f "$codex_path/Package.swift" ]]; then
    run_package_checks "Codex stress client" "$codex_path"
  else
    printf '\n-- Codex stress client not found at %s; skipped --\n' "$codex_path"
  fi
fi

motel_path="${RATATUI_MOTEL_PATH:-$workspace/motel-swift}"
if ! $skip_motel; then
  if [[ -f "$motel_path/Package.swift" ]]; then
    run_package_checks "Motel stress client" "$motel_path"
  else
    printf '\n-- Motel stress client not found at %s; skipped --\n' "$motel_path"
  fi
fi

herdr_path="${RATATUI_HERDR_PATH:-$workspace/herdr-swift}"
if ! $skip_herdr; then
  if [[ -f "$herdr_path/Package.swift" ]]; then
    run_package_checks "Herdr stress client" "$herdr_path"
  else
    printf '\n-- Herdr stress client not found at %s; skipped --\n' "$herdr_path"
  fi
fi
