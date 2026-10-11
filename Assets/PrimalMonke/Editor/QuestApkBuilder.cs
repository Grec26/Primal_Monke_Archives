using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.XR.Management;
using UnityEngine;
using UnityEngine.XR.OpenXR;
using UnityEngine.XR.OpenXR.Features;

namespace PrimalMonke.Editor
{
    public static class QuestApkBuilder
    {
        // Also callable with -executeMethod PrimalMonke.Editor.QuestApkBuilder.Build
        // after configuring OpenXR in the editor and selecting Android.
        [MenuItem("Primal Monke/Build Quest APK")]
        public static void Build()
        {
            if (!BuildPipeline.IsBuildTargetSupported(BuildTargetGroup.Android, BuildTarget.Android))
                throw new BuildFailedException("Install Android Build Support, SDK/NDK, and OpenJDK using Unity Hub.");
            if (EditorUserBuildSettings.activeBuildTarget != BuildTarget.Android)
                throw new BuildFailedException("Switch to Android in File > Build Settings, then run Build Quest APK again.");

            var xr = XRGeneralSettingsPerBuildTarget.XRGeneralSettingsForBuildTarget(BuildTargetGroup.Android);
            bool hasOpenXR = false;
            if (xr != null && xr.Manager != null)
                foreach (var loader in xr.Manager.activeLoaders)
                    if (loader != null && loader.GetType().Name == "OpenXRLoader") hasOpenXR = true;
            if (!hasOpenXR || !xr.InitManagerOnStart)
                throw new BuildFailedException("Enable OpenXR and Initialize XR on Startup for Android in XR Plug-in Management.");
            var settings = OpenXRSettings.GetSettingsForBuildTargetGroup(BuildTargetGroup.Android);
            bool quest = false, controllers = false;
            if (settings != null)
                foreach (var feature in settings.GetFeatures<OpenXRFeature>())
                {
                    if (feature == null || !feature.enabled) continue;
                    string type = feature.GetType().Name;
                    if (type.IndexOf("MetaQuest", StringComparison.OrdinalIgnoreCase) >= 0) quest = true;
                    if (type == "OculusTouchControllerProfile") controllers = true;
                }
            if (!quest || !controllers)
                throw new BuildFailedException("Enable Meta Quest Support and Oculus Touch Controller Profile in Android OpenXR settings; resolve Project Validation issues.");

            const string scene = "Assets/PrimalMonke/Scenes/Forest.unity";
            if (!File.Exists(scene)) ForestSceneBuilder.Build();
            if (!File.Exists(scene)) throw new BuildFailedException("Forest scene generation was canceled.");
            if (!UnityEditor.SceneManagement.EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo())
                throw new BuildFailedException("Build canceled while saving scenes.");

            PlayerSettings.companyName = "Primal Monke";
            PlayerSettings.productName = "Primal Monke Forest Chase";
            PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Android, "com.primalmonke.forestchase");
            PlayerSettings.SetScriptingBackend(NamedBuildTarget.Android, ScriptingImplementation.IL2CPP);
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel29;
            PlayerSettings.Android.targetSdkVersion = AndroidSdkVersions.AndroidApiLevelAuto;
            // Local sideload build: use Unity's debug signing, never a release keystore.
            PlayerSettings.Android.useCustomKeystore = false;
            EditorUserBuildSettings.buildAppBundle = false;
            Directory.CreateDirectory("Builds/Android");
            string output = "Builds/Android/PrimalMonke.apk";
            var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = new[] { scene }, locationPathName = output,
                target = BuildTarget.Android, options = BuildOptions.Development
            });
            if (report.summary.result != BuildResult.Succeeded)
                throw new BuildFailedException("APK build failed: " + report.summary.result + "; inspect the Unity Console.");
            Debug.Log("Quest APK created: " + Path.GetFullPath(output));
        }
    }
}
