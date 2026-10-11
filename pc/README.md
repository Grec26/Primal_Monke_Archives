# Primal Monke for Windows

[Download PrimalMonke-Windows.zip](PrimalMonke-Windows.zip?raw=true), extract it, and run **PrimalMonke.exe**. The ZIP contains the Windows 64-bit executable with its game data embedded. Unity and Godot are not required to play. Windows 10/11 and a graphics driver supporting OpenGL 3.3 are recommended.

## Controls

- **WASD**: move.
- Hold **right mouse button**: look.
- **Space**: jump.
- **E**: tag a nearby monkey.
- **R**: restart a solo round or a round you host.
- **Tab**: open or close the multiplayer menu.

## Play with Quest

Use the matching **0.2.0** [Quest APK](../apk/README.md). This native Windows game and that native Quest build share one multiplayer protocol. The Unity and browser versions use their own separate projects.

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

The Windows x64 release export was built in the cloud workspace. PE architecture, ZIP integrity, embedded game resources, and game-resource checksums were verified. The exact embedded game pack also started successfully on Linux Godot in headless mode. All 16 native smoke checks passed, and a three-process ENet session passed with mixed desktop and simulated VR poses. Windows execution, Windows/Quest device connections, real headset controllers, and rendering/performance still need hardware testing.

The download is about **34.3 MiB**; the extracted executable is about **99.8 MiB**. Exact sizes and SHA-256 hashes are recorded in [build-info.json](build-info.json). The ZIP checksum is also available in [PrimalMonke-Windows.zip.sha256](PrimalMonke-Windows.zip.sha256).
