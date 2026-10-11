# Primal Monke Quest APK

[Download PrimalMonke-Quest.apk](https://github.com/Grec26/Primal_Monke_Archives/raw/refs/heads/main/apk/PrimalMonke-Quest.apk)

Native Godot OpenXR **0.2.0** test build, approximately **85 MB** (81 MiB), for an ARM64 Quest headset. This separate port includes forest chase, arm-driven movement, five AI monkeys, and co-op crossplay with the matching [Windows build](../pc/README.md). The Unity project remains separate.

Sideload through SideQuest or `adb install -r PrimalMonke-Quest.apk`, then launch **Primal Monke** from Unknown Sources. Enable developer mode and authorize USB debugging first.

Press right **B** for the multiplayer menu; point the right controller and pull the trigger. Choose **Host**, or enter another player's IPv4 address with the keypad and choose **Join**. Use the same Wi-Fi or forward UDP 7777 on the host's router. [Full crossplay instructions](../quest-native/README.md#crossplay).

Android signature, ZIP integrity, native-library alignment, ARM64 libraries, OpenXR loader/manifest, and packaged resources are checked during export. Native gameplay and real ENet sessions are tested headlessly. No headset is available; real headset launch, controllers, performance, and comfort remain untested.

[Build details](build-info.json) · [SHA256 checksum](PrimalMonke-Quest.apk.sha256) · [Source and rebuild instructions](../quest-native/README.md)
