# Primal Monke — native PC and Quest crossplay

This **Godot 4.6.3 OpenXR port** builds a Windows x64 executable and an ARM64 Quest APK. Version **0.4.0** adds an original monkey app icon, main menu, real loading screens, and a multiplayer waiting lobby. It retains desktop/PC VR modes, PlayFab registration and sign-in, and tools for selected developer accounts. Up to eight PC and Quest players share the same five monkeys, score, and 90-second round, with visible remote head/hand avatars. It also runs solo. The Unity 2021.3.21f1 and WebXR projects remain separate single-player versions.

## Install on Windows

Download [PrimalMonke-Windows.zip](../pc/README.md) and extract every file into one folder. **Play-Desktop.bat** forces keyboard/mouse mode. Use WASD, hold right mouse to look, Space to jump, E to tag nearby monkeys, and R to restart. **F1** opens the main menu; **Tab / right B** opens the main menu in solo play and the room menu during multiplayer. Game data and the custom Windows icon are embedded in PrimalMonke.exe.

## PC VR mode

Connect your headset and start its active **OpenXR runtime**, then launch **Play-PCVR.bat**. For Quest PC VR, use Link/Air Link with the Meta OpenXR runtime, or another configured PC OpenXR connection. SteamVR can also serve as the active runtime for a supported headset. The runtime must support OpenGL graphics bindings. The game uses tracked headset/controllers and the same arm-driven locomotion as the standalone APK; desktop WASD is disabled while VR is active.

The launcher passes `--xr-mode on -- --play-mode=pcvr`. Desktop mode passes `--xr-mode off -- --play-mode=desktop`. Launching the EXE directly retains automatic VR detection. In the main menu, **PC VR** / **Desktop** switches mode by restarting the game; leave an online session first. If the headset runtime is unavailable and the game starts in desktop mode, a visible message asks you to start the runtime and retry. A restart requires a fresh account sign-in but keeps the saved device identity.

The executable is unsigned; Windows may ask you to confirm running an unfamiliar application. Windows launch and real PC VR rendering remain untested in this Linux workspace.

## Install on Quest

Enable developer mode on your headset, connect over USB, and authorize debugging. Sideload `PrimalMonke-Quest.apk` using SideQuest or:

```sh
adb install -r PrimalMonke-Quest.apk
```

Launch **Primal Monke** from the headset's Unknown Sources applications. The package identifier is `com.grec26.primalmonke`. This is a debug-signed local test build, not a store release.

## Play

Startup shows a loading screen whose progress follows the forest resource load, then opens the main menu. No round starts until you choose **Play solo** or the host starts a multiplayer room. **Account** opens registration/sign-in; **Multiplayer lobby** opens the player list and connection controls. Desktop and headset menus use the same actions; in VR, aim the right controller and pull its trigger.

Solo and shared-round preparation also show a loading screen. Leaving during preparation cancels the transition. Open the main menu during a round and choose **Resume game** to continue without resetting your score or timer. Returning from the room menu to **Main menu** disconnects that room.

Push the floor, tree trunks, branches, or rocks with your tracked controllers to move and climb. Release a push to launch. Touch each brown monkey's torso to tag it; tagged monkeys turn orange and stop. Tag all five within 90 seconds. The world board near spawn displays the round. Press right **A** to restart.

Tracking/focus loss pauses that player's movement and tags; the shared round continues while another player is active. Recenter clears hand anchors and launch momentum. The APK is intended for a Quest headset, not a phone.

## Crossplay

1. Install matching **0.4.0** PC and Quest builds. Connect devices to the same local network; guest Wi-Fi/client isolation can prevent connections.
2. Choose **Multiplayer lobby** in the main menu. In VR, aim the right controller at a button and pull its trigger. The keypad enters an IPv4 address.
3. One player selects **Host** and shares the IP shown in the lobby. On Windows, allow the game through the firewall for your private network.
4. Other players enter that IP and select **Join**. The player list updates as friends arrive. Movement, bot tags, and the countdown stay paused while the room waits.
5. The host selects **Start match**. All players prepare the shared forest and enter the round. Each tag contributes to the shared score; only the host can restart. **Leave** returns to an offline lobby for another connection; **Main menu** disconnects and returns to the main screen. Losing the host during play returns clients to solo; disconnecting during preparation returns to the offline lobby.

ENet uses **UDP port 7777**, with a maximum of eight players including the host. Across the internet, forward UDP 7777 to the host and join the host's public IPv4 address. Networks behind carrier-grade NAT may need a VPN with direct peer connectivity. There is no hosted lobby service, relay, automatic NAT traversal, matchmaking, voice chat, or player-versus-player infection mode. This is co-op against the original AI monkeys. The browser and Unity projects cannot join these native sessions.

The host simulates bots and owns the round. Clients send their head/hand poses at 20 Hz; host snapshots update shared state at 10 Hz. Remote poses are validated for finite values, arena/reach bounds, and the current round. Stale poses stop tagging after two seconds. Cosmetic remote avatars have no collision. This prototype trusts each player's local movement; it is intended for testing with friends.

## Accounts

The native builds use PlayFab title **1A7D9B**. Each device initially signs in automatically with a private, randomly generated device credential; PlayFab creates its account if needed. Ordinary solo and crossplay games remain available when PlayFab is offline.

Open **Account** from the main menu or lobby, or press **F3 / left X**. To register, enter a username (3–20 characters), email address, and password (6–100 characters), then select **Register**. When signed in with an anonymous device account, registration adds credentials to that same account and preserves its PlayFab ID. When signed out, registration creates a new account. An already registered account must sign out before registering another.

Select **Sign in** with your email or username and password to use an existing account on PC or Quest. Email is used if that field is filled; otherwise username is used. VR supports field selection and a controller-operated keyboard with letters, numbers, uppercase, symbols, space, and backspace. Passwords are masked and cleared when submitted or the menu closes; they and session tickets are never saved to disk or logged. The separate **Device account** option restores this device's automatic account. The game signs into that device account on the next launch; credentials used to sign into another account are not remembered.

The random device credential stays in local user data. PC and Quest devices normally start with different IDs; deleting that data can create a new ID. Registered credentials let you sign back into your existing account on another device. Registration does not grant developer privileges, even if the chosen username matches a developer's public ID.

Client endpoints used are LoginWithCustomID, RegisterPlayFabUser, AddUsernamePassword, LoginWithPlayFab, LoginWithEmailAddress, GetAccountInfo and GetTitleData. They must be allowed by the title's API policy. All requests use HTTPS; no PlayFab secret key is shipped. Actual signup/login cannot be tested from the current cloud network policy.

## Developer access

Both registered and device accounts use the title-owned developer ID list. There are no default developer accounts or first-player grants.

1. Start the game with internet access. Open **Account** from the multiplayer menu, or press **F3 / left X**. Read the signed-in account's **PlayFab ID**.
2. In PlayFab Game Manager for title **1A7D9B**, open **Content → Title Data**. Add the key **PrimalMonkeDeveloperIds**. Its value must be a JSON array of selected real PlayFab IDs, for example:

   ```json
   ["YOUR_PC_PLAYFAB_ID", "YOUR_QUEST_PLAYFAB_ID"]
   ```

   These are placeholders: replace them with the IDs shown in the game. An empty value/list, missing key, malformed JSON, or unmatched ID grants nobody access. No developer IDs have been supplied or granted by this repository update.
3. Save the title data and select **Refresh access** in the game's Account menu. PlayFab can cache title data for approximately a minute; retry after that if needed.
4. A verified developer can open the tools with **F2 / left Y** and select VR buttons with the right aim ray and trigger.

Tools include round restart, +30 seconds (maximum 300 seconds), bot freeze/resume, tag all monkeys, local respawn, and a diagnostics overlay. Shared-round tools require a running round and the developer to be the host or offline. Developer clients can use local respawn/diagnostics; they cannot change the host's shared round. Every handler checks current permission and authority, including direct calls. There are no remote developer-action RPCs, shared menu passwords, nickname-based permissions, or command-line unlocks.

The client verifies the login ticket's actual account owner using GetAccountInfo, then reads the title-owned developer list using GetTitleData. Client APIs cannot edit this list. Sign-out, failed permission checks, and expired access close the menu and clear ongoing freeze/diagnostic effects. Access refreshes every four minutes and expires after five; PlayFab caching can delay revocation by roughly another minute. Keep each developer device's local credential private. No PlayFab secret key is required or bundled.

## Rebuild

1. Install **Godot 4.6.3** and its matching export templates from the official distribution.
2. Install a full JDK **17** and the Android SDK. In Godot Editor Settings → Export → Android, configure their paths and a debug keystore.
3. Install Android **platform 36**, **build-tools 36.1.0**, platform-tools, and **NDK 29.0.14206865**. The official Godot template compiles against API 36; this local Quest export targets API 32 with minimum API 29.
4. Open `quest-native/project.godot`. Choose Project → Install Android Build Template. This creates the ignored `android/` build folder and version marker. Gradle is required for OpenXR.
5. Export the **Quest** preset as a debug APK, or run:

   ```sh
   godot --headless --xr-mode off --path quest-native --export-debug Quest ../Builds/Android/PrimalMonke-Quest.apk
   ```

   The preset has `runnable=false` to avoid device polling in headless build environments; this does not affect manual installation. You may enable one-click deployment locally.

For Windows, install the matching Windows export template and export the **Windows** preset as release, or use `GODOT_BIN=/path/to/godot quest-native/scripts/build_pc.sh`. The helper produces `Builds/Windows/PrimalMonke.exe` and a ZIP containing the executable, desktop/PC VR launchers, and instructions. The ZIP keeps the repository download below GitHub's per-file limit.

The supplied default action map includes headset and controller bindings. The generic OpenXR loader is used without a separate vendors plugin; Android XR/Quest firmware must provide a compatible runtime. The forest and monkeys are original primitive art. The Quest preset includes Android internet permission for ENet connections.

## Verification

Build metadata and checksums live in [`apk/`](../apk/) and [`pc/`](../pc/). Export verification checks Android signing, ZIP integrity, native-library alignment, manifest/loader, packaged game files, Windows PE architecture, and embedded game data.

All **16 native smoke checks**, **134 account/developer-access checks**, **49 frontend checks**, and **129 three-process ENet integration assertions** passed. The integration run mixes desktop input and simulated VR head/hand poses. Frontend checks cover real threaded startup, waiting rooms, explicit host start, pause/resume, overlay restoration, canceled loads, a disconnect during local loading, and first-pose placement of the VR main menu. Account checks use mocked PlayFab responses; headless runs never register real players. Desktop menus were rendered with Linux software OpenGL at 1280×720 and 960×540. Simulated world panels were also inspected for layering. Live PlayFab sign-in is unverified because the cloud network policy blocks the title endpoint. Windows/Quest hardware and real PC VR rendering remain untested.

Native headless smoke checks exercise scene startup, five monkeys, hand-floor sweep, capsule gravity collision, countdown, menu movement/pause/history handling, tracking pause, simulated XR head/controller poses, controller tracking loss, recenter history clearing, unique tags, round completion, restart, and timeout:

```sh
godot --headless --xr-mode off --path quest-native --script tests/smoke_check.gd
```

Real ENet host/client integration checks run separate headless processes over localhost:

```sh
GODOT_BIN=/path/to/godot quest-native/tests/run_crossplay_check.sh
```

Developer/account and mode checks:

```sh
godot --headless --xr-mode off --path quest-native --script tests/developer_access_check.gd -- --play-mode=pcvr
```

Main menu, loading, and lobby checks:

```sh
godot --headless --xr-mode off --path quest-native --script tests/frontend_check.gd
```

These checks exercise shared rounds, remote avatars, accepted/rejected tag poses, host restart authority, pause behavior, and disconnections. They do not substitute for tests on a Windows PC, Quest headset, or a real LAN/router.

Headset launch, real controller movement, rendering/performance, and comfort still require a Quest test. For that test: push off the floor, climb and release a trunk, collide with a cliff, tag a monkey, finish or time out the round, restart, recenter, and briefly interrupt tracking. Confirm there are no unexpected jumps or continued movement when tracking pauses.
