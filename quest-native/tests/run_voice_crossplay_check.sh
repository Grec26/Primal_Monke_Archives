#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
test_dir="$(mktemp -d /tmp/primal-monke-voice-XXXXXX)"
declare -a children=()
cleanup() {
  for child in "${children[@]}"; do kill "$child" 2>/dev/null || true; done
}
trap cleanup EXIT
for role in host speaker listener; do
  mkdir -p "$test_dir/$role/data" "$test_dir/$role/config" "$test_dir/$role/cache"
  XDG_DATA_HOME="$test_dir/$role/data" XDG_CONFIG_HOME="$test_dir/$role/config" XDG_CACHE_HOME="$test_dir/$role/cache" \
    timeout 20s "$godot_bin" --headless --xr-mode off --max-fps 60 --path "$project_dir" \
    --script tests/voice_crossplay_check.gd -- "voice-role=$role" >"$test_dir/$role.log" 2>&1 &
  children+=("$!")
  if [[ "$role" == host ]]; then sleep 0.3; fi
done
failed=0
for child in "${children[@]}"; do wait "$child" || failed=1; done
for role in host speaker listener; do cat "$test_dir/$role.log"; done
if rg -q 'SCRIPT ERROR|^ERROR:|FAIL \[' "$test_dir"/*.log; then failed=1; fi
printf 'Voice transport logs: %s\n' "$test_dir"
exit "$failed"
