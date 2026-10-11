# Primal Monke Quest APK

[Download PrimalMonke-Quest.apk](https://github.com/Grec26/Primal_Monke_Archives/raw/refs/heads/main/apk/PrimalMonke-Quest.apk)

Native Godot OpenXR **0.5.1** test build for an ARM64 Quest headset, with arm-driven movement, updated menus/loading screens, a climbable forest/treehouse, original audio, and eight-player crossplay with the matching [Windows/PC VR build](../pc/README.md). Choose Co-op chase against five AI monkeys or multiplayer Player Tag. Profiles add public names/PFPs and cosmetic levels; tutorials and opt-in voice are available from the main menu. Unity 2021.3.21f1 and WebXR remain separate single-player projects.

## Install and play

Enable developer mode, connect over USB, and authorize debugging. Sideload through SideQuest or:

```sh
adb install -r PrimalMonke-Quest.apk
```

Launch **Primal Monke** from Unknown Sources. The package is `com.grec26.primalmonke`; it is debug-signed for local headset testing.

On first launch, choose **Create account** or **Continue as guest**. Select **Play solo** or **Multiplayer lobby** from the main menu. Push surfaces with tracked hands to move/climb, touch monkeys or players to tag, and press right **A** to restart a solo/hosted round. Right **B** opens the main menu offline or room menu online. Aim the right controller and pull its trigger for menu buttons.

## Crossplay and voice

Host a room or enter the host's IPv4 address with the keypad and choose **Join**. Use the same local network; connections use **UDP 7777**. The host selects **Co-op chase** or **Player Tag**, then **Start match**. Player Tag needs at least two players. [Full crossplay instructions](../quest-native/README.md#crossplay).

Open **Voice** from the main menu. Voice starts **off** and the microphone starts **muted**. Enable voice to listen, then explicitly unmute to speak; Quest requests microphone permission at that point. Lobby voice reaches the room; game voice reaches players within **14 metres**. Volume and individual player mutes are available. Leaving the room or disabling voice stops capture/playback and mutes the mic.

## Accounts, profiles, and developer tools

**Account / left X** uses PlayFab title **1A7D9B**. Create an account with username, email, and password, or sign into an existing account using the controller keyboard. Returning registered players sign in again; passwords and session tickets are never saved. Guest play remains available without account creation. Feedback includes validation/network/PlayFab support codes, including **PF-5847** if PlayFab supplies that unknown numeric diagnostic. [Account and error instructions](../quest-native/README.md#accounts).

**Profile** changes your public name/PFP and shows cosmetic XP/levels. PNG/JPEG uploads are limited to **4 MiB** and **4096 × 4096**, then cropped to a small square PNG. Quest uses its system file picker; if unavailable, upload on PC and sign into the same account to sync. The picker remains untested on hardware. Names, pictures, and levels are public to room players; signed-in profiles use public PlayFab User Data, with local progress retained when cloud sync fails. [Profile details](../quest-native/README.md#profiles-and-levels).

Only selected verified IDs in `PrimalMonkeDeveloperIds` see **Dev tools** in Main and Account; **left Y** also opens the menu. No IDs have been granted by this update; the title owner configures them through PlayFab. [Developer setup](../quest-native/README.md#developer-access).

## Verification

Release checks cover Android signing, ZIP integrity, native-library alignment, ARM64 libraries, OpenXR loader/manifest, microphone/internet permissions, and packaged resources. Headless suites cover gameplay, accounts/developer access, updated UI, error codes, profiles/levels, tutorials/audio, and voice privacy. Three-process ENet runs cover co-op, Player Tag, and synthetic voice packets. A read-only production PlayFab probe with `CreateAccount=false` verified transport; it created no player.

Real headset launch, controllers, system picker, microphone/speaker output, rendering/performance, comfort, and successful live signup/profile sync remain untested. Exact sizes, checksums, and release check results are in [build-info.json](build-info.json).

[SHA-256 checksum](PrimalMonke-Quest.apk.sha256) · [Source and rebuild instructions](../quest-native/README.md)
