#!/usr/bin/env bash
set -euo pipefail

pm_project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
pm_godot_bin="${GODOT_BIN:-godot}"

if ! command -v "$pm_godot_bin" >/dev/null 2>&1; then
  printf 'Godot is required. Install it or set GODOT_BIN to its executable.\n' >&2
  exit 1
fi
if ! command -v rg >/dev/null 2>&1; then
  printf 'ripgrep (rg) is required to inspect the crossplay test logs.\n' >&2
  exit 1
fi

pm_signal_dir="$(mktemp -d "${TMPDIR:-/tmp}/primal-monke-crossplay.XXXXXX")"
pm_roles=(host client1 client2)
pm_pids=()
pm_log_paths=()
pm_statuses=()
pm_failed=0
pm_has_timeout=0
if command -v timeout >/dev/null 2>&1; then
  pm_has_timeout=1
fi

pm_cleanup() {
  local pm_pid
  for pm_pid in "${pm_pids[@]}"; do
    if kill -0 "$pm_pid" 2>/dev/null; then
      kill "$pm_pid" 2>/dev/null || true
    fi
  done
  for pm_pid in "${pm_pids[@]}"; do
    wait "$pm_pid" 2>/dev/null || true
  done
  printf '\nCrossplay signal directory retained: %s\n' "$pm_signal_dir"
  printf 'Log: %s\n' "${pm_log_paths[@]}"
}
trap pm_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Crossplay signal directory: %s\n' "$pm_signal_dir"
for pm_role in "${pm_roles[@]}"; do
  pm_log="$pm_signal_dir/$pm_role.log"
  pm_role_dir="$pm_signal_dir/$pm_role"
  mkdir -p "$pm_role_dir/data" "$pm_role_dir/config" "$pm_role_dir/cache"
  pm_log_paths+=("$pm_log")
  printf 'Starting %s; log: %s\n' "$pm_role" "$pm_log"
  if [ "$pm_has_timeout" -eq 1 ]; then
    XDG_DATA_HOME="$pm_role_dir/data" XDG_CONFIG_HOME="$pm_role_dir/config" \
      XDG_CACHE_HOME="$pm_role_dir/cache" timeout --kill-after=5s 50s "$pm_godot_bin" \
      --headless --xr-mode off --path "$pm_project_dir" \
      --script res://tests/crossplay_check.gd -- \
      "--role=$pm_role" "--signals=$pm_signal_dir" >"$pm_log" 2>&1 &
  else
    XDG_DATA_HOME="$pm_role_dir/data" XDG_CONFIG_HOME="$pm_role_dir/config" \
      XDG_CACHE_HOME="$pm_role_dir/cache" "$pm_godot_bin" --headless --xr-mode off --path "$pm_project_dir" \
      --script res://tests/crossplay_check.gd -- \
      "--role=$pm_role" "--signals=$pm_signal_dir" >"$pm_log" 2>&1 &
  fi
  pm_pids+=("$!")
done

for pm_index in "${!pm_pids[@]}"; do
  if wait "${pm_pids[$pm_index]}"; then
    pm_statuses+=(0)
  else
    pm_status=$?
    pm_statuses+=("$pm_status")
    pm_failed=1
  fi
done
pm_pids=()

for pm_index in "${!pm_roles[@]}"; do
  printf '\n%s log (exit %s):\n' \
    "${pm_roles[$pm_index]}" "${pm_statuses[$pm_index]}"
  cat "${pm_log_paths[$pm_index]}"
done

# Generic Godot ERROR lines can be expected when tests forge RPC authority.
if rg -n '(SCRIPT ERROR|Parse Error|FAIL:)' "${pm_log_paths[@]}"; then
  pm_failed=1
else
  pm_rg_status=$?
  if [ "$pm_rg_status" -ne 1 ]; then
    printf 'Could not inspect all crossplay logs.\n' >&2
    pm_failed=1
  fi
fi

if [ "$pm_failed" -ne 0 ]; then
  printf '\nCrossplay checks failed. Review the retained logs.\n' >&2
  exit 1
fi
printf '\nCrossplay checks passed for host, client1, and client2.\n'
