# Primal Monke Quest APK

[Download PrimalMonke-Quest.apk](https://github.com/Grec26/Primal_Monke_Archives/raw/refs/heads/main/apk/PrimalMonke-Quest.apk)

Native Godot OpenXR test build, approximately **85 MB** (81 MiB), for an ARM64 Quest headset. This is a separate port, not a compiled Unity APK. It includes the offline forest chase, arm-driven movement, five AI monkeys, and restart.

Sideload through SideQuest or `adb install -r PrimalMonke-Quest.apk`, then launch **Primal Monke** from Unknown Sources. Enable developer mode and authorize USB debugging first.

Android v2 signature, ZIP integrity, 16 KB native library alignment, ARM64 libraries, OpenXR loader and manifest, and game resources were verified. Thirteen native smoke checks passed. No headset was available; real headset launch, controllers, performance, and comfort remain untested.

[Build details](build-info.json) · [SHA256 checksum](PrimalMonke-Quest.apk.sha256) · [Source and rebuild instructions](../quest-native/README.md)
