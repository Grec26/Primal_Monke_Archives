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

pm_write_launcher() {
  local pm_launcher="$1"
  local pm_xr_mode="$2"
  local pm_play_mode="$3"
  printf '%s\r\n' \
    '@echo off' \
    'setlocal' \
    'if not exist "%~dp0PrimalMonke.exe" (' \
    '  echo PrimalMonke.exe is missing. Extract the complete ZIP into one folder first.' \
    '  pause' \
    '  exit /b 1' \
    ')' \
    "start \"\" /D \"%~dp0\" \"%~dp0PrimalMonke.exe\" --xr-mode $pm_xr_mode -- --play-mode=$pm_play_mode" \
    'if errorlevel 1 (' \
    '  echo Primal Monke could not start.' \
    '  pause' \
    '  exit /b 1' \
    ')' \
    'exit /b 0' > "$pm_output_dir/$pm_launcher"
}

pm_write_launcher Play-Desktop.bat off desktop
pm_write_launcher Play-PCVR.bat on pcvr
cat > "$pm_output_dir/README.txt" <<'README'
Primal Monke 0.4.0 for Windows

Extract every file from the ZIP into the same folder before playing.

Play-Desktop.bat: keyboard and mouse play, without starting VR.
Play-PCVR.bat: tracked headset and controller play using OpenXR.
Connect your headset and start its active OpenXR runtime first. For a Quest
headset, use Quest Link/Air Link or another configured PC OpenXR connection.

The game loads its forest resources before showing the main menu. Choose Play
solo for a new round, Multiplayer lobby to meet friends, or Account to manage
sign-in. PC VR and Desktop switch play modes while you are offline. Resume
game returns to an existing round without starting over.

Desktop controls: WASD move, hold right mouse to look, Space jump, E tag, and
R restart a solo round or a round you host. F1 opens the main menu. Tab opens
the main menu offline or the lobby online; right B serves the same role in VR.
Point with the right controller and press its trigger to select menu buttons.

The game automatically signs in a saved device account with PlayFab at startup.
Account opens with F3 on desktop or left X in VR and shows your public PlayFab
ID, sign-in status, and access role. You can play with that device account.

To register, enter a username (3-20 characters), email, and password (6-100
characters), then choose Register. Registering while signed into a device
account adds credentials to that same account and preserves its PlayFab ID.
Sign out before registering if you want a separate new account.

To use your registered account on another PC or Quest, enter its email or
username and password, then choose Sign in. Email takes precedence when both
fields are filled; clear Email to sign in by username. Passwords are masked,
cleared after submission or closing Account, and never saved by the game.
The VR form includes a keyboard with lowercase, uppercase, and symbols.

Developer tools are available only to accounts approved by the game's owner.
After your PlayFab ID is added to the server's developer list, choose Refresh
access in Account. F2 on desktop or left Y in VR opens the developer menu.
Use the same registered account on PC and Quest to keep the same approved ID.

To play with standalone Quest, install the matching 0.4.0 native APK. Connect
both devices to the same local network and choose Multiplayer lobby. Choose
Host on one device, then enter its IPv4 address and choose Join on the other.
Wait until the lobby roster contains your friends. The host chooses Start
match to load the shared forest and begin the round. Movement, tagging, and
the round timer stay paused while the room is staging. UDP port 7777 is used.

Full instructions and source:
https://github.com/Grec26/Primal_Monke_Archives/tree/main/pc
Developer access setup:
https://github.com/Grec26/Primal_Monke_Archives/tree/main/quest-native#developer-access
README

(
  cd "$pm_output_dir"
  zip -q -9 -FS PrimalMonke-Windows.zip PrimalMonke.exe Play-Desktop.bat Play-PCVR.bat README.txt
)
printf 'Windows executable: %s\nDownload ZIP: %s\n' \
  "$pm_output_dir/PrimalMonke.exe" "$pm_output_dir/PrimalMonke-Windows.zip"
