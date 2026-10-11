#!/usr/bin/env bash
set -euo pipefail
pm_project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
pm_godot_bin="${GODOT_BIN:-godot}"
mkdir -p "$pm_project_dir/../Builds/Android"
"$pm_godot_bin" --headless --xr-mode off --path "$pm_project_dir" --export-debug Quest "$pm_project_dir/../Builds/Android/PrimalMonke-Quest.apk"
