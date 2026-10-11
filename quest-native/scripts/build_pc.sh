#!/usr/bin/env bash
set -euo pipefail

pm_project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
pm_godot_bin="${GODOT_BIN:-godot}"
pm_output_dir="$pm_project_dir/../Builds/Windows"

if ! command -v "$pm_godot_bin" >/dev/null 2>&1; then
  printf 'Godot 4.6.3 is required. Install it or set GODOT_BIN to its executable.\n' >&2
  exit 1
fi
if ! command -v zip >/dev/null 2>&1; then
  printf 'The zip command is required to package the Windows build.\n' >&2
  exit 1
fi
pm_godot_version="$("$pm_godot_bin" --version)"
case "$pm_godot_version" in
  4.6.3.*) ;;
  *) printf 'This project requires Godot 4.6.3 and matching export templates.\n' >&2; exit 1 ;;
esac

mkdir -p "$pm_output_dir"
"$pm_godot_bin" --headless --xr-mode off --path "$pm_project_dir" \
  --export-release Windows "$pm_output_dir/PrimalMonke.exe"
(
  cd "$pm_output_dir"
  zip -q -9 PrimalMonke-Windows.zip PrimalMonke.exe
)
printf 'Windows executable: %s\nDownload ZIP: %s\n' \
  "$pm_output_dir/PrimalMonke.exe" "$pm_output_dir/PrimalMonke-Windows.zip"
