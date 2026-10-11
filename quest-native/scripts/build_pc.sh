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
Primal Monke 0.7.0 for Windows

Extract all four files from the ZIP into the same folder before playing.
Play-Desktop.bat: keyboard and mouse play.
Play-PCVR.bat: tracked headset and controller play using OpenXR.
Connect your headset and start its active OpenXR runtime first. Quest PC VR
uses Link/Air Link or another configured PC OpenXR connection.

The game loads the forest, then offers Create account or Continue as guest
on first launch. Choose Play solo for a 90-second monkey chase, or Multiplayer
lobby for Co-op chase / Player Tag. The main menu also opens Account, Profile,
Tutorial, Settings, and Voice. Resume game continues your round without resetting it.
Map creator lets everyone build local maps while offline. Place platforms,
blocks, walls, trees and rocks; move/resize/rotate/recolor/duplicate/delete;
undo/redo; save/load six slots; try Blank/Parkour/Climb presets. Desktop has
WASD/QE fly camera, right mouse look, mouse wheel zoom, and a numeric inspector.
Headsets use paged aim/trigger controls, with right B to reopen the editor.
F8 / right B returns from playtest. R / right A respawns during playtest.
Custom maps have no XP/timer/bots and stay on this device; multiplayer keeps
the original forest. Save before closing the app; exit restores the forest.
PC VR and Desktop restart the game to switch modes while you are offline.

Desktop controls:
WASD move; hold right mouse to look; Space jump; E tag a nearby monkey/player.
R restarts solo or a hosted round. F1 opens the main menu.
Tab opens the main menu offline or the room menu online.
F3 Account; F4 Tutorial; F5 Profile/PFP; F6 Voice; F7 Settings.
F2 Developer tools, only when your account has permission.
Hold V during captured gameplay to talk after enabling voice.

VR controls:
Push solid surfaces with tracked hands to move/climb; release to launch.
Touch a target with a hand to tag. Right A restarts solo/a hosted round.
Right B opens the main/room menu; left X opens Account; left Y opens approved
developer tools. Aim the right controller and pull its trigger for menu buttons.
Tutorial, Profile, Settings, and Voice are available from the main menu.
The expanded forest connects cave, treehouse and lookout routes.

Accounts are optional for solo and direct multiplayer. Guests stay offline
unless they explicitly choose an account action. Returning registered players
get a fresh Sign in prompt; passwords and session tickets are never saved.

To register, choose Create account and enter a username (3-20 characters),
email, and password (6-100 characters). Enter in Password submits the selected
mode. Invalid local input keeps the password for correction; real submission
or closing Account clears it. Registering while signed into a device account
adds credentials to that same account and preserves its PlayFab ID.
Choose Sign in with an existing email or username and password. Email takes
precedence when both fields are filled. VR has a keyboard with symbols/case.
Support codes identify local/network/PlayFab failures; unknown numeric provider
codes such as PF-5847 are kept for troubleshooting.

Profile sets your public name and picture and shows cosmetic XP/level.
Upload PNG/JPEG up to 4 MiB and 4096 x 4096; pictures become a small square PNG.
Your name, picture, and level are public to room players. Guest progress stays
local; signed-in accounts can sync public PlayFab profiles. Failed cloud sync
retains local progress; use Retry sync. XP grants no developer privileges.

To play with Quest, install the matching 0.7.0 APK and use the same local network.
Choose Multiplayer lobby; Host on one device, then enter its IPv4 address and
Join on the others. Up to eight players share a room using UDP 7777.
The host selects Co-op chase or Player Tag, then Start match. Gameplay/timer
remain paused in the waiting lobby. Co-op shares five AI monkeys and a score.
Player Tag needs at least two players: the orange player is IT and passes that
role by tagging another player. Only the host can restart.

Voice starts off and your mic starts muted. Open Voice, enable listening, then
explicitly unmute or hold V during gameplay to speak. Releasing V mutes again.
VR uses the microphone button. Lobby voice reaches the room; game voice reaches
players within 14 metres. Volume/per-player mute controls are available.
Leaving a room or disabling voice stops capture/playback and mutes the mic.

Developer tools require the owner's verified PlayFab ID approval. After your
ID is added to the title-owned list, choose Refresh access in Account.
Dev tools appears in Main and Account after verification; F2 / left Y also works.
Round controls add pause/resume, end round and bot pace for the host or solo
player. Map testing adds local landmark teleports, up to eight markers and
collision outlines. These tools clear on access revocation or round restart.
No IDs are granted by this build. Names, PFPs, and XP cannot grant access.

Windows/Quest hardware, real microphone/speaker output, performance, and
successful live signup/profile writes still require device testing.

Full instructions and source:
https://github.com/Grec26/Primal_Monke_Archives/tree/main/pc
Native guide and developer setup:
https://github.com/Grec26/Primal_Monke_Archives/tree/main/quest-native
README

(
  cd "$pm_output_dir"
  zip -q -9 -FS PrimalMonke-Windows.zip PrimalMonke.exe Play-Desktop.bat Play-PCVR.bat README.txt
)
printf 'Windows executable: %s\nDownload ZIP: %s\n' \
  "$pm_output_dir/PrimalMonke.exe" "$pm_output_dir/PrimalMonke-Windows.zip"
