using UnityEngine;
using UnityEngine.XR;

namespace PrimalMonke
{
    public sealed class TagGame : MonoBehaviour
    {
        public ArmLocomotion player;
        public TextMesh board;
        public MonkeyBot[] monkeys;
        float remaining = 90, cooldown;
        int score;
        bool finished, restartHeld;

        void Start() { Restart(); }
        void Restart()
        {
            remaining = 90; cooldown = 2; score = 0; finished = false;
            player.Respawn();
            foreach (var monkey in monkeys) monkey.ResetBot();
        }
        void Update()
        {
            var device = InputDevices.GetDeviceAtXRNode(XRNode.RightHand);
            device.TryGetFeatureValue(CommonUsages.primaryButton, out bool restart);
            if (restart && !restartHeld) Restart();
            restartHeld = restart;
            if (!player.Tracking)
            {
                board.text = "PRIMAL MONKE\nPut on your headset\nand turn on both controllers.\n\nPush surfaces with your hands to move.\nTag all 5 monkeys in 90 seconds.\nRight A / primary button: restart";
                return;
            }
            if (!finished)
            {
                remaining -= Time.deltaTime; cooldown -= Time.deltaTime;
                foreach (var monkey in monkeys)
                {
                    if (monkey.Tagged || cooldown > 0) continue;
                    if (Vector3.Distance(player.leftHand.position, monkey.transform.position + Vector3.up * .7f) < .65f ||
                        Vector3.Distance(player.rightHand.position, monkey.transform.position + Vector3.up * .7f) < .65f)
                    { monkey.Tag(); score++; cooldown = .35f; }
                }
                finished = score == monkeys.Length || remaining <= 0;
            }
            board.text = "PRIMAL MONKE\n" + (finished ? (score == monkeys.Length ? "ALL MONKEYS TAGGED!" : "TIME'S UP!") : "FOREST CHASE") +
                "\nTagged: " + score + " / " + monkeys.Length + "    Time: " + Mathf.CeilToInt(Mathf.Max(0, remaining)) +
                "\nPush the ground and trees to move.\nRight A / primary button: restart";
            foreach (var monkey in monkeys) monkey.Active = !finished;
        }
    }
}
