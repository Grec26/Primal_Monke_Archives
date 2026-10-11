# Primal Monke Quest APK

[Download PrimalMonke-Quest.apk](https://github.com/Grec26/Primal_Monke_Archives/raw/refs/heads/main/apk/PrimalMonke-Quest.apk)

Native Godot OpenXR **0.4.0** test build for an ARM64 Quest headset. This separate port includes a custom monkey icon, main menu, loading screens, an eight-player waiting lobby, forest chase, arm-driven movement, five AI monkeys, co-op crossplay with the matching [Windows/PC VR build](../pc/README.md), and PlayFab-controlled developer tools. The Unity project remains separate. Exact size and checksum are in [build-info.json](build-info.json).

Sideload through SideQuest or `adb install -r PrimalMonke-Quest.apk`, then launch **Primal Monke** from Unknown Sources. Enable developer mode and authorize USB debugging first.

Press right **B** for the multiplayer menu; point the right controller and pull the trigger. Choose **Host**, or enter another player's IPv4 address with the keypad and choose **Join**. Use the same Wi-Fi or forward UDP 7777 on the host's router. [Full crossplay instructions](../quest-native/README.md#crossplay).

The game initially signs this device into PlayFab title **1A7D9B**. **Account / left X** also supports username/email registration and sign-in, using a controller-operated keyboard. [Account instructions](../quest-native/README.md#accounts). Only selected IDs in the title's `PrimalMonkeDeveloperIds` list get the **left Y** developer menu. [Developer setup](../quest-native/README.md#developer-access). No IDs have been granted yet; the title owner adds selected account IDs through PlayFab.

Android signature, ZIP integrity, native-library alignment, ARM64 libraries, OpenXR loader/manifest, and packaged resources are checked during export. Native gameplay and real ENet sessions are tested headlessly. No headset is available; real headset launch, controllers, performance, and comfort remain untested.

All 16 gameplay, 134 mocked account/developer-access, 49 frontend checks, and 129 three-process ENet assertions pass. The game starts at the main menu; choose **Play solo** or **Multiplayer lobby**, then have the host press **Start match**. Live PlayFab sign-in remains unverified because this cloud's network policy blocks the title API; the game remains playable without an account connection.

[Build details](build-info.json) · [SHA256 checksum](PrimalMonke-Quest.apk.sha256) · [Source and rebuild instructions](../quest-native/README.md)
