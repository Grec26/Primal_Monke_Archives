# Primal Monke — native PC and Quest crossplay

This **Godot 4.6.3 OpenXR port** builds a Windows x64 executable and an ARM64 Quest APK. Version **0.2.0** adds co-op crossplay: up to eight PC and Quest players share the same five monkeys, score, and 90-second round, with visible remote head/hand avatars. It also runs solo. The Unity 2021.3.21f1 and WebXR projects remain separate single-player versions.

## Install on Windows

Download [PrimalMonke-Windows.zip](../pc/README.md), extract it, and run **PrimalMonke.exe**. Game data is embedded in the executable. Use WASD, hold right mouse to look, Space to jump, E to tag nearby monkeys, R to restart, and **Tab** to open the multiplayer menu. A compatible active OpenXR runtime also enables PC VR; otherwise the game uses desktop controls. To force desktop mode, launch `PrimalMonke.exe --xr-mode off`.

The executable is unsigned; Windows may ask you to confirm running an unfamiliar application. Windows launch and real PC VR rendering remain untested in this Linux workspace.

## Install on Quest

Enable developer mode on your headset, connect over USB, and authorize debugging. Sideload `PrimalMonke-Quest.apk` using SideQuest or:

```sh
adb install -r PrimalMonke-Quest.apk
```

Launch **Primal Monke** from the headset's Unknown Sources applications. The package identifier is `com.grec26.primalmonke`. This is a debug-signed local test build, not a store release.

## Play

Push the floor, tree trunks, branches, or rocks with your tracked controllers to move and climb. Release a push to launch. Touch each brown monkey's torso to tag it; tagged monkeys turn orange and stop. Tag all five within 90 seconds. The world board near spawn displays the round. Press right **A** to restart.

Tracking/focus loss pauses that player's movement and tags; the shared round continues while another player is active. Recenter clears hand anchors and launch momentum. The APK is intended for a Quest headset, not a phone.

## Crossplay

1. Install matching **0.2.0** PC and Quest builds. Connect devices to the same local network; guest Wi-Fi/client isolation can prevent connections.
2. Open the menu with **Tab** on desktop or **right B** on Quest. In VR, aim the right controller at a button and pull its trigger. The keypad enters an IPv4 address.
3. One player selects **Host**. Open their menu to read the host's local IP address. On Windows, allow the game through the firewall for your private network.
4. Other players enter that IP and select **Join**. Each tag contributes to the shared score. Only the host can restart. **Leave** returns to solo; losing the host also returns clients to solo.

ENet uses **UDP port 7777**, with a maximum of eight players including the host. Across the internet, forward UDP 7777 to the host and join the host's public IPv4 address. Networks behind carrier-grade NAT may need a VPN with direct peer connectivity. There is no hosted lobby service, relay, automatic NAT traversal, matchmaking, voice chat, or player-versus-player infection mode. This is co-op against the original AI monkeys. The browser and Unity projects cannot join these native sessions.

The host simulates bots and owns the round. Clients send their head/hand poses at 20 Hz; host snapshots update shared state at 10 Hz. Remote poses are validated for finite values, arena/reach bounds, and the current round. Stale poses stop tagging after two seconds. Cosmetic remote avatars have no collision. This prototype trusts each player's local movement; it is intended for testing with friends.

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

For Windows, install the matching Windows export template and export the **Windows** preset as release, or use `GODOT_BIN=/path/to/godot quest-native/scripts/build_pc.sh`. The helper produces `Builds/Windows/PrimalMonke.exe` and a ZIP containing that executable. The ZIP keeps the repository download below GitHub's per-file limit.

The supplied default action map includes headset and controller bindings. The generic OpenXR loader is used without a separate vendors plugin; Android XR/Quest firmware must provide a compatible runtime. The forest and monkeys are original primitive art. The Quest preset includes Android internet permission for ENet connections.

## Verification

Build metadata and checksums live in [`apk/`](../apk/) and [`pc/`](../pc/). Export verification checks Android signing, ZIP integrity, native-library alignment, manifest/loader, packaged game files, Windows PE architecture, and embedded game data.

All **16 native smoke checks** and the **three-process ENet integration checks** passed. The integration run mixes desktop input and simulated VR head/hand poses. The exact exported Windows game pack starts on Linux, and the exported APK resources pass scene/menu/ENet startup checks on Linux.

Native headless smoke checks exercise scene startup, five monkeys, hand-floor sweep, capsule gravity collision, countdown, menu movement/pause/history handling, tracking pause, simulated XR head/controller poses, controller tracking loss, recenter history clearing, unique tags, round completion, restart, and timeout:

```sh
godot --headless --xr-mode off --path quest-native --script tests/smoke_check.gd
```

Real ENet host/client integration checks run separate headless processes over localhost:

```sh
GODOT_BIN=/path/to/godot quest-native/tests/run_crossplay_check.sh
```

These checks exercise shared rounds, remote avatars, accepted/rejected tag poses, host restart authority, pause behavior, and disconnections. They do not substitute for tests on a Windows PC, Quest headset, or a real LAN/router.

Headset launch, real controller movement, rendering/performance, and comfort still require a Quest test. For that test: push off the floor, climb and release a trunk, collide with a cliff, tag a monkey, finish or time out the round, restart, recenter, and briefly interrupt tracking. Confirm there are no unexpected jumps or continued movement when tracking pauses.
