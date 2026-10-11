# Primal Monke for Windows

[Download PrimalMonke-Windows.zip](PrimalMonke-Windows.zip?raw=true) and extract **all four files** into one folder. Choose **Play-Desktop.bat** for keyboard/mouse or **Play-PCVR.bat** for a tracked headset and controllers. The ZIP contains the Windows x64 executable with embedded game data and icon, both launchers, and instructions. Unity and Godot are not required to play. Windows 10/11 and a graphics driver supporting OpenGL 3.3 are recommended.

## Start playing

Version **0.5.0** adds updated menus, first-run registration, support error codes, picture uploads/PFPs, cosmetic levels, Player Tag, optional voice, tutorials, original audio, and a climbable treehouse. Startup loads the forest, then offers **Create account** or **Continue as guest** on first launch. The main menu opens **Play solo**, **Multiplayer lobby**, **Account**, **Profile**, **Tutorial**, and **Voice**. **Resume game** continues an existing round without resetting it.

Press **F1** for the main menu. **Tab** on desktop or right **B** in VR opens the main menu offline and the room menu online. In a waiting room, movement, tags, and the timer remain paused until the host chooses **Start match**.

## PC VR

Connect your headset, start its active PC OpenXR runtime, and launch **Play-PCVR.bat**. For Quest, establish Link/Air Link or another configured PC OpenXR connection first. SteamVR can also provide the active runtime for a supported headset; it must support OpenGL graphics bindings. The PC VR launcher enables OpenXR and the desktop launcher disables it. **PC VR** / **Desktop** in the main menu restarts the game to switch modes while offline.

In VR, push surfaces with tracked controllers to move and climb. Touch monkeys or players with a hand to tag. Right **A** restarts a solo or hosted round; right **B** opens the main/room menu. Aim the right controller and pull its trigger to select menu buttons.

## Controls

| Key | Action |
| --- | --- |
| WASD | Move |
| Hold right mouse | Look |
| Space | Jump |
| E | Tag a nearby monkey/player |
| R | Restart a solo or hosted round |
| F1 | Main menu |
| Tab | Main menu offline / room menu online |
| F3 | Account; left X in VR |
| F2 | Developer tools with permission; left Y in VR |
| F4 | Tutorial |
| F5 | Profile and picture upload |
| F6 | Voice settings |
| Hold V | Talk during captured gameplay after enabling voice |

Tutorial, Profile, and Voice are also available through the main menu in a headset. Tutorial exercises check movement, jumping/hand contact, and accepted tags; they can be skipped or replayed.

## Accounts and profiles

First launch offers **Create account** and **Continue as guest**. Gameplay works without sign-in. Guests remain offline unless they explicitly choose an account action. Returning registered players see **Sign in** again because passwords and session tickets are never saved.

Open **Account / F3 / left X**. To register, choose **Create account** and enter a username (3–20 characters), email, and password (6–100 characters). **Enter** in Password submits the selected mode. Invalid local details preserve the password for correction; actual submission or closing Account clears it. Registering while signed into an anonymous device account preserves that account's PlayFab ID. Sign out to create a separate account.

Choose **Sign in** with your existing email or username and password to use the same account on PC and Quest. Email takes precedence when both fields are filled. VR has a keyboard with lowercase, uppercase, symbols, and spaces. Feedback includes support codes for validation, connectivity, and PlayFab failures; unknown numeric provider codes such as **PF-5847** remain visible for troubleshooting. [Full account/error instructions](../quest-native/README.md#accounts).

Open **Profile / F5** to change your public name, upload/reset a PFP, view XP/level, or retry cloud sync. Pictures must be local PNG/JPEG files up to **4 MiB** and **4096 × 4096**; they are cropped to a small square PNG. Names, pictures, and levels are visible to other room players. Guest progress stays local; verified accounts can sync the public **PMProfileV1** PlayFab profile after its initial read succeeds. Failed reads/writes preserve local progress for retry.

XP is cosmetic and managed by the client. Co-op awards 10 XP per shared bot tag and 25 XP for finishing all five; Player Tag awards 20 XP per accepted player tag and 15 XP for finishing without being IT. XP grants no developer permissions. [Profile details](../quest-native/README.md#profiles-and-levels).

The owner approves selected PlayFab IDs through title **1A7D9B**'s `PrimalMonkeDeveloperIds` list. After approval, choose **Refresh access** in Account, then open **F2 / left Y**. No IDs are granted by this update. [Developer access setup](../quest-native/README.md#developer-access).

## Play with Quest

Use the matching **0.5.0** [Quest APK](../apk/README.md). Unity 2021.3.21f1 and WebXR remain separate single-player projects.

1. Connect PC and Quest to the same local network, then choose **Multiplayer lobby**.
2. One device chooses **Host** and shares the local IPv4 address shown in its lobby. Other players enter it and choose **Join**.
3. The host selects **Co-op chase** or **Player Tag** while the lobby is waiting. Player Tag needs at least two players.
4. Check the roster, then have the host choose **Start match**. All devices load before the shared 90-second round starts.
5. In Co-op chase, tag five AI monkeys together. In Player Tag, the orange player is IT and transfers the role by tagging another player. Only the host can restart.

Up to eight players share one room. If Windows asks, allow the game through its firewall on your private network. Connections use **UDP 7777**; guest Wi-Fi isolation can block them. There is no hosted matchmaking or relay. [Crossplay instructions](../quest-native/README.md#crossplay).

## Voice chat

Voice starts **off** with your microphone **muted**. Open **Voice / F6**, choose **Enable voice** to listen, then explicitly unmute or hold **V** during gameplay to speak. Releasing V mutes again. In VR, use the microphone button. Lobby voice reaches the room; match voice reaches players within **14 metres**. Use the volume control and individual player mute buttons as needed. Leaving the room or disabling voice stops capture/playback and mutes the mic.

## Rebuild

Install Godot **4.6.3** and its matching official Windows export templates. Export the **Windows** preset from `quest-native/project.godot` in release mode, or with Bash and `zip` run:

```sh
./quest-native/scripts/build_pc.sh
```

Set `GODOT_BIN` if needed. The helper writes the executable and ZIP to `Builds/Windows/`.

## Verification

Release checks cover Windows PE architecture/icon, ZIP integrity, launcher arguments, embedded resources, and game-resource checksums. Headless suites cover gameplay, account/developer access, registration UI/error codes, loading/menu flow, profiles/XP, tutorials/audio, and voice handling. Three-process ENet tests cover co-op, Player Tag, and synthetic voice packets using desktop/simulated VR poses. Mock account tests create no real players; a production probe with `CreateAccount=false` verified PlayFab transport.

Windows execution, real Windows/Quest connections, headset controls, microphone/speaker output, rendering/performance, and successful live signup/profile writes remain untested. Exact download sizes, hashes, and release check results are recorded in [build-info.json](build-info.json). The ZIP checksum is in [PrimalMonke-Windows.zip.sha256](PrimalMonke-Windows.zip.sha256).
