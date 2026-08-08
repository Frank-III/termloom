#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
packages=(
  "Packages/TermLoomOverlays"
  "Packages/TermLoomTextArea"
  "Packages/TermLoomDevTools"
  "Packages/TermLoomMacros"
  "Examples/Postcat"
  "Examples/DiffScope"
)

printf '\n== minimal core (no default traits) ==\n'
(
  cd "$root"
  swift build --disable-default-traits --product TermLoom
)

for package in "${packages[@]}"; do
  printf '\n== %s ==\n' "$package"
  (
    cd "$root/$package"
    swift format lint --strict --recursive Sources Tests Package.swift
    swift test
  )
done

printf '\n== TermLoomDevTools without its default Overlays trait ==\n'
(
  cd "$root/Packages/TermLoomDevTools"
  swift build --disable-default-traits --product TermLoomDevTools
)

printf '\n== Postcat with optional DevTools trait ==\n'
(
  cd "$root/Examples/Postcat"
  swift build --traits DevTools --product termloom-postcat
)

printf '\n== Postcat dependency boundary ==\n'
dependencies="$(cd "$root/Examples/Postcat" && swift package show-dependencies --format text)"
printf '%s\n' "$dependencies"
if grep -Eq 'swift-snapshot-testing|swift-custom-dump|swift-syntax' <<<"$dependencies"; then
  echo "Postcat resolved a testing or macro dependency unexpectedly" >&2
  exit 1
fi

printf '\n== DiffScope dependency boundary ==\n'
dependencies="$(cd "$root/Examples/DiffScope" && swift package show-dependencies --format text)"
printf '%s\n' "$dependencies"
if grep -Eq 'swift-highlight|swift-snapshot-testing|swift-custom-dump|swift-syntax' <<<"$dependencies"; then
  echo "DiffScope resolved an unused syntax, testing, or macro dependency" >&2
  exit 1
fi
