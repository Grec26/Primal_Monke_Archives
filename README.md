# Primal Monke — Forest Chase

An original single-player Unity VR tag prototype inspired by arm-driven locomotion. Includes a climbable forest, five fleeing AI monkeys, and a 90-second round. No Gorilla Tag assets or code are used. Multiplayer is not implemented.

A separate **WebXR browser version** is available in [`web/`](web/README.md). It supports headset controllers and an on-screen mode without modifying the Unity project.

## Open and play

1. Install **Unity 2021.3.21f1** using Unity Hub. For standalone Quest builds, include Android Build Support, SDK/NDK tools, and OpenJDK.
2. Open this repository folder as a Unity project and allow the pinned OpenXR and XR Management packages to resolve.
3. The editor generates `Assets/PrimalMonke/Scenes/Forest.unity` on first import. Alternatively choose **Primal Monke → Create Forest Scene**. Rebuilding replaces the generated scene; save your work first.
4. Under **Edit → Project Settings → XR Plug-in Management**, enable **OpenXR** for your target platform. Add your controller interaction profile (for example, Oculus Touch) under OpenXR. Run **Project Validation** and resolve required issues.
5. For PC VR, connect your headset, start its OpenXR runtime, open Forest, and press Play. For Quest, switch to Android in Build Settings, enable OpenXR for Android and the Meta Quest feature group, select ARM64 and IL2CPP, and build to the device. Use floor tracking and a configured guardian boundary.

## Build a Quest APK

After completing OpenXR setup above, switch to **Android** in **File → Build Settings**. Enable **Initialize XR on Startup**, **Meta Quest Support**, and **Oculus Touch Controller Profile** for Android, then resolve OpenXR Project Validation issues.

Choose **Primal Monke → Build Quest APK**. The command checks required XR settings and creates `Builds/Android/PrimalMonke.apk` using ARM64, IL2CPP, and debug signing for local testing. It updates Android player settings and leaves release signing out of this prototype workflow. This APK requires a Quest headset; it is not a phone game.

Enable developer mode on your Quest, connect it over USB, authorize debugging in the headset, then install using:

```sh
adb install -r Builds/Android/PrimalMonke.apk
```

Launch **Primal Monke Forest Chase** from the headset's Unknown Sources apps. A Unity installation with Android Build Support and an activated license is required to produce the APK. No APK has been compiled in this cloud workspace.

## Controls

- Push against the floor, tree trunks, branches, or rocks with your hands to move and climb. Release a push to launch.
- Touch each monkey's torso with either hand to tag it. Tagged monkeys turn orange and stop.
- Tag all five in 90 seconds. The board near spawn shows your progress.
- Right controller primary button (A on Touch): restart.
- Timer and locomotion pause if the headset or either controller loses tracking. There is no keyboard simulation.

## Code

`ArmLocomotion` uses XR poses, swept hand spheres, a capsule body, gravity, and limited launch velocity. Arena surfaces use layer 8. `MonkeyBot` has simple obstacle-reactive wandering and fleeing, without a navigation mesh. `TagGame` manages scoring, time, and restart. `ForestSceneBuilder` generates original primitive art and the build scene.

## Verification

Unity and a headset runtime are not installed in this cloud workspace. Unity compilation, package resolution, headset play, comfort, and Android builds remain unverified.

Headset smoke check: push off the floor, brace and climb a tree, release to jump, collide with a cliff, tag a monkey and confirm its color changes, finish or time out a round, and restart. Disconnect a controller to check the timer pauses. Check the Console for errors. Tune movement and test comfort before distributing builds.
