using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;

namespace PrimalMonke.Editor
{
    [InitializeOnLoad]
    public static class ForestSceneBuilder
    {
        const string ScenePath = "Assets/PrimalMonke/Scenes/Forest.unity";
        static ForestSceneBuilder()
        {
            EditorApplication.delayCall += () =>
            {
                if (!System.IO.File.Exists(ScenePath) && !EditorApplication.isPlayingOrWillChangePlaymode) Build();
            };
        }
        static Material Mat(string name, Color color)
        {
            string path = "Assets/PrimalMonke/Materials/" + name + ".mat";
            var existing = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (existing != null) return existing;
            var material = new Material(Shader.Find("Standard")) { color = color };
            material.SetFloat("_Glossiness", .05f);
            AssetDatabase.CreateAsset(material, path);
            return material;
        }
        static GameObject Shape(string name, PrimitiveType type, Vector3 position, Vector3 scale,
            Material material, Transform parent = null, bool solid = true)
        {
            var go = GameObject.CreatePrimitive(type);
            go.name = name; go.transform.SetParent(parent, false);
            go.transform.localPosition = position; go.transform.localScale = scale;
            go.GetComponent<Renderer>().sharedMaterial = material;
            if (solid) go.layer = 8;
            else Object.DestroyImmediate(go.GetComponent<Collider>());
            return go;
        }
        [MenuItem("Primal Monke/Create Forest Scene")]
        public static void Build()
        {
            if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
            System.IO.Directory.CreateDirectory("Assets/PrimalMonke/Scenes");
            System.IO.Directory.CreateDirectory("Assets/PrimalMonke/Materials");
            AssetDatabase.Refresh();
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            var grass = Mat("Moss", new Color(.16f, .32f, .16f));
            var wood = Mat("Bark", new Color(.29f, .17f, .09f));
            var leaf = Mat("Leaves", new Color(.12f, .36f, .20f));
            var stone = Mat("Stone", new Color(.35f, .40f, .38f));
            var fur = Mat("Fur", new Color(.42f, .22f, .12f));
            var face = Mat("Face", new Color(.68f, .49f, .3f));
            var eyes = Mat("Eyes", Color.black);
            var hands = Mat("Hands", new Color(.72f, .44f, .23f));
            RenderSettings.ambientMode = AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(.6f, .7f, .65f);
            RenderSettings.fog = true; RenderSettings.fogColor = new Color(.27f, .43f, .38f);
            RenderSettings.fogMode = FogMode.Linear; RenderSettings.fogStartDistance = 18; RenderSettings.fogEndDistance = 45;
            var sun = new GameObject("Sun").AddComponent<Light>();
            sun.type = LightType.Directional; sun.intensity = 1.1f;
            sun.transform.rotation = Quaternion.Euler(45, -35, 0);
            Shape("Forest floor", PrimitiveType.Cube, new Vector3(0, -.5f, 0), new Vector3(32, 1, 32), grass);
            Shape("North cliff", PrimitiveType.Cube, new Vector3(0, 3, 16), new Vector3(34, 7, 1), stone);
            Shape("South cliff", PrimitiveType.Cube, new Vector3(0, 3, -16), new Vector3(34, 7, 1), stone);
            Shape("East cliff", PrimitiveType.Cube, new Vector3(16, 3, 0), new Vector3(1, 7, 32), stone);
            Shape("West cliff", PrimitiveType.Cube, new Vector3(-16, 3, 0), new Vector3(1, 7, 32), stone);
            for (int i = 0; i < 12; i++)
            {
                float angle = i * Mathf.PI * 2 / 12;
                Vector3 location = new Vector3(Mathf.Cos(angle) * 10, 0, Mathf.Sin(angle) * 10);
                Shape("Tree trunk " + i, PrimitiveType.Cylinder, location + Vector3.up * 3, new Vector3(1.1f, 3, 1.1f), wood);
                Shape("Canopy " + i, PrimitiveType.Sphere, location + Vector3.up * 6.7f, new Vector3(5, 3, 5), leaf, solid: false);
                Shape("Branch " + i, PrimitiveType.Cube, location + Vector3.up * 2.5f, new Vector3(3, .3f, 1), wood);
            }
            Shape("Low rock", PrimitiveType.Cube, new Vector3(-3, .5f, 1), new Vector3(3, 1, 2), stone);
            Shape("High rock", PrimitiveType.Cube, new Vector3(-4, 1.25f, 3), new Vector3(2, 2.5f, 2), stone);
            var rig = new GameObject("VR Monkey Rig"); rig.transform.position = new Vector3(0, .15f, -5);
            var controller = rig.AddComponent<CharacterController>();
            controller.radius = .22f; controller.height = 1.6f; controller.center = Vector3.up * .8f;
            controller.skinWidth = .015f; controller.minMoveDistance = 0;
            var locomotion = rig.AddComponent<ArmLocomotion>();
            var cameraObject = new GameObject("Head"); cameraObject.tag = "MainCamera";
            cameraObject.transform.SetParent(rig.transform, false); cameraObject.transform.localPosition = Vector3.up * 1.6f;
            var camera = cameraObject.AddComponent<Camera>(); camera.nearClipPlane = .03f; camera.farClipPlane = 65;
            camera.clearFlags = CameraClearFlags.SolidColor; camera.backgroundColor = RenderSettings.fogColor;
            cameraObject.AddComponent<AudioListener>(); locomotion.head = cameraObject.transform;
            locomotion.leftHand = Shape("Left hand", PrimitiveType.Sphere, new Vector3(-.3f, 1, .4f), Vector3.one * .18f, hands, rig.transform, false).transform;
            locomotion.rightHand = Shape("Right hand", PrimitiveType.Sphere, new Vector3(.3f, 1, .4f), Vector3.one * .18f, hands, rig.transform, false).transform;
            var boardObject = new GameObject("Round board");
            boardObject.transform.position = new Vector3(0, 2.4f, -1.5f);
            boardObject.transform.rotation = Quaternion.Euler(0, 180, 0);
            var board = boardObject.AddComponent<TextMesh>();
            board.font = Resources.GetBuiltinResource<Font>("Arial.ttf");
            boardObject.GetComponent<MeshRenderer>().sharedMaterial = board.font.material;
            board.anchor = TextAnchor.MiddleCenter; board.alignment = TextAlignment.Center;
            board.fontSize = 48; board.characterSize = .045f; board.color = new Color(1, .9f, .63f);
            board.text = "PRIMAL MONKE\nFOREST CHASE";
            var game = new GameObject("Tag Round").AddComponent<TagGame>();
            game.player = locomotion; game.board = board; game.monkeys = new MonkeyBot[5];
            for (int i = 0; i < 5; i++)
            {
                var botObject = new GameObject("Forest monkey " + (i + 1));
                botObject.transform.position = new Vector3((i - 2) * 3, .1f, 5);
                var botController = botObject.AddComponent<CharacterController>();
                botController.height = 1.2f; botController.radius = .35f; botController.center = Vector3.up * .6f;
                var bot = botObject.AddComponent<MonkeyBot>(); bot.player = locomotion.head;
                bot.fur = Shape("Body", PrimitiveType.Sphere, Vector3.up * .65f, new Vector3(.8f, 1, .6f), fur, botObject.transform, false).GetComponent<Renderer>();
                Shape("Head", PrimitiveType.Sphere, new Vector3(0, 1.12f, .05f), Vector3.one * .55f, fur, botObject.transform, false);
                Shape("Muzzle", PrimitiveType.Sphere, new Vector3(0, 1.02f, .29f), new Vector3(.36f, .24f, .2f), face, botObject.transform, false);
                foreach (float side in new[] { -1f, 1f })
                {
                    Shape("Eye", PrimitiveType.Sphere, new Vector3(side * .12f, 1.18f, .29f), Vector3.one * .07f, eyes, botObject.transform, false);
                    Shape("Arm", PrimitiveType.Capsule, new Vector3(side * .52f, .5f, .05f), new Vector3(.2f, .43f, .2f), fur, botObject.transform, false);
                }
                game.monkeys[i] = bot;
            }
            EditorSceneManager.SaveScene(scene, ScenePath);
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
            AssetDatabase.SaveAssets();
            Debug.Log("Forest created. Enable OpenXR and your controller interaction profile for headset play.");
        }
    }
}
