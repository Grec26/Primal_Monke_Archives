# Primal Monke for Windows

[Download PrimalMonke-Windows.zip](PrimalMonke-Windows.zip?raw=true) and extract **all four files** into the same folder. Choose **Play-Desktop.bat** for keyboard and mouse play, or **Play-PCVR.bat** for a tracked headset and controllers. The ZIP contains the Windows 64-bit executable with its game data embedded, both launchers, and brief instructions. Unity and Godot are not required to play. Windows 10/11 and a graphics driver supporting OpenGL 3.3 are recommended.

## PC VR

Connect your headset, start its PC OpenXR runtime, and launch **Play-PCVR.bat**. For a Quest headset, establish Quest Link/Air Link or another configured PC OpenXR connection first. Set your headset software as the active OpenXR runtime when needed. The PC VR launcher explicitly enables OpenXR; the desktop launcher disables it. You can also switch modes from the game's public menu.

In VR, push against surfaces with your tracked controllers to move and climb, touch monkeys to tag them, and press right **A** to restart a round you host. Right **B** opens the multiplayer menu; point with the right controller and press its trigger to select buttons.

## Controls

- **WASD**: move.
- Hold **right mouse button**: look.
- **Space**: jump.
- **E**: tag a nearby monkey.
- **R**: restart a solo round or a round you host.
- **Tab**: open or close the multiplayer menu.
- **F3**: open or close Account; in VR, press left **X**.
- **F2**: open or close developer tools when your account has access; in VR, press left **Y**.

## Accounts and developer access

The game automatically signs in a saved device account with PlayFab at startup. Open **Account** with **F3** or left **X** to see your public **PlayFab ID**, sign-in status, and access role. You can play with the device account or register credentials from this menu.

To register, enter a **username of 3–20 characters**, an **email**, and a **password of 6–100 characters**, then choose **Register**. Registering while signed into a device account adds credentials to that account and **preserves its PlayFab ID**. Sign out first if you want to create a separate account. In VR, select a field and use the on-screen keyboard, including uppercase, symbols, and spaces.

To use the same registered account on another PC or Quest, enter its **email or username** and password, then choose **Sign in**. Email takes precedence when both fields are filled; clear Email to use Username. The game masks password inputs, clears them after submission or closing Account, and does not save passwords. Each startup signs in the saved local device identity; choose credential sign-in when you want an account registered on another device.

The owner approves selected PlayFab IDs through the server's `PrimalMonkeDeveloperIds` list. After approval, select **Refresh access** in Account, then open developer tools with **F2** or left **Y**. See the [developer access setup](../quest-native/README.md#developer-access). Signing into the same registered account on PC and Quest gives both devices the same approved ID. Separate device accounts have separate IDs.

## Play with Quest

Use the matching **0.3.0** [Quest APK](../apk/README.md). This native Windows game and that native Quest build share one multiplayer protocol. The Unity and browser versions use their own separate projects.

1. Connect the PC and Quest to the same local network.
2. On either device, open the multiplayer menu and choose **Host**. The menu shows that device's local IP address.
3. On the other device, enter the host's IPv4 address and choose **Join**. On Windows, press **Tab**; on Quest, press right **B** and point at the menu with the right controller, using the trigger to select buttons and enter the address.
4. Tag the five AI monkeys together before the shared 90-second timer expires. The host controls restarts. Up to eight players can join the same session.

If Windows asks, allow the game through its firewall on your private network. Connections use **UDP 7777**. Guest Wi-Fi isolation can prevent devices from connecting. There is no public matchmaking service; this build is intended for direct connections on a local network.

## Rebuild

Install Godot **4.6.3** and its matching official Windows export templates. Export the **Windows** preset from `quest-native/project.godot` in release mode, or on a system with Bash and `zip` run:

```sh
./quest-native/scripts/build_pc.sh
```

Set `GODOT_BIN` if the executable is not named `godot`. The script writes the executable and download ZIP to `Builds/Windows/`.

## Verification

The Windows x64 release export was built in the cloud workspace. PE architecture, ZIP integrity, both launcher arguments, embedded game resources, and game-resource checksums were verified. The exact embedded game pack also started successfully on Linux Godot in headless mode. All 16 native smoke checks and 134 account, registration, developer access, and play mode checks passed. Mock UI checks and an independent review verified password masking, clearing, whitespace preservation, and all 95 printable ASCII keyboard characters. A three-process ENet session passed with mixed desktop and simulated VR poses. Live PlayFab sign-in/registration, Windows execution, Windows/Quest device connections, real headset controllers, and rendering/performance still need testing.

The download is about **34.3 MiB**; the extracted executable is about **99.8 MiB**. Exact sizes and SHA-256 hashes are recorded in [build-info.json](build-info.json). The ZIP checksum is also available in [PrimalMonke-Windows.zip.sha256](PrimalMonke-Windows.zip.sha256).
