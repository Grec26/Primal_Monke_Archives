using UnityEngine;
using UnityEngine.XR;

namespace PrimalMonke
{
    [RequireComponent(typeof(CharacterController))]
    public sealed class ArmLocomotion : MonoBehaviour
    {
        public Transform head, leftHand, rightHand;
        public LayerMask climbable = 1 << 8;
        public float handRadius = .09f, maxArmLength = 1.45f, maxLaunchSpeed = 7f;
        public bool LeftContact { get; private set; }
        public bool RightContact { get; private set; }
        public bool Tracking { get; private set; }
        CharacterController body;
        Vector3 leftAnchor, rightAnchor, velocity, pushVelocity;
        bool initialized, wasContact;
        readonly System.Collections.Generic.List<XRInputSubsystem> subsystems = new();

        void Awake() { body = GetComponent<CharacterController>(); }
        void Start()
        {
            SubsystemManager.GetSubsystems(subsystems);
            foreach (var subsystem in subsystems)
                subsystem.TrySetTrackingOriginMode(TrackingOriginModeFlags.Floor);
        }

        bool Pose(XRNode node, Transform target)
        {
            var device = InputDevices.GetDeviceAtXRNode(node);
            if (!device.TryGetFeatureValue(CommonUsages.isTracked, out bool tracked) || !tracked ||
                !device.TryGetFeatureValue(CommonUsages.devicePosition, out Vector3 position) ||
                !device.TryGetFeatureValue(CommonUsages.deviceRotation, out Quaternion rotation)) return false;
            target.localPosition = position;
            target.localRotation = rotation;
            return true;
        }

        Vector3 Reach(Transform hand)
        {
            return head.position + Vector3.ClampMagnitude(hand.position - head.position, maxArmLength);
        }

        Vector3 Resolve(Vector3 anchor, Vector3 desired, out bool contact)
        {
            Vector3 delta = desired - anchor;
            if (delta.sqrMagnitude > .000001f && Physics.SphereCast(anchor, handRadius,
                delta.normalized, out RaycastHit hit, delta.magnitude, climbable, QueryTriggerInteraction.Ignore))
            {
                contact = true;
                return hit.point + hit.normal * (handRadius + .003f);
            }
            contact = Physics.CheckSphere(desired, handRadius + .005f, climbable, QueryTriggerInteraction.Ignore);
            return contact ? anchor : desired;
        }

        void Update()
        {
            bool headTracked = Pose(XRNode.Head, head);
            bool leftTracked = Pose(XRNode.LeftHand, leftHand);
            bool rightTracked = Pose(XRNode.RightHand, rightHand);
            Tracking = headTracked && leftTracked && rightTracked;
            if (!Tracking) { initialized = false; velocity = pushVelocity = Vector3.zero; wasContact = false; return; }
            float dt = Mathf.Min(Time.deltaTime, .05f);
            if (dt <= 0) return;
            body.height = Mathf.Clamp(head.localPosition.y, .6f, 2.2f);
            body.center = new Vector3(head.localPosition.x, body.height / 2 + .02f, head.localPosition.z);
            if (!initialized)
            {
                leftAnchor = Reach(leftHand); rightAnchor = Reach(rightHand); initialized = true;
            }
            Vector3 leftDesired = Reach(leftHand), rightDesired = Reach(rightHand);
            Vector3 leftResolved = Resolve(leftAnchor, leftDesired, out bool lc);
            Vector3 rightResolved = Resolve(rightAnchor, rightDesired, out bool rc);
            LeftContact = lc; RightContact = rc;
            int contacts = (lc ? 1 : 0) + (rc ? 1 : 0);
            Vector3 correction = ((lc ? leftResolved - leftDesired : Vector3.zero) +
                (rc ? rightResolved - rightDesired : Vector3.zero)) / Mathf.Max(1, contacts);
            Vector3 before = transform.position;
            if (contacts > 0)
            {
                body.Move(correction);
                pushVelocity = Vector3.Lerp(pushVelocity, (transform.position - before) / dt, 1 - Mathf.Exp(-18 * dt));
                velocity = Vector3.zero;
            }
            else
            {
                if (wasContact) velocity = Vector3.ClampMagnitude(pushVelocity * 1.15f, maxLaunchSpeed);
                velocity += Physics.gravity * dt;
                if (body.isGrounded && velocity.y < 0) velocity.y = -1;
                CollisionFlags flags = body.Move(velocity * dt);
                if ((flags & CollisionFlags.Above) != 0) velocity.y = Mathf.Min(velocity.y, 0);
            }
            wasContact = contacts > 0;
            leftAnchor = lc ? leftResolved : Reach(leftHand);
            rightAnchor = rc ? rightResolved : Reach(rightHand);
            // Display the constrained hand at the actual surface rather than inside a wall.
            leftHand.position = leftAnchor; rightHand.position = rightAnchor;
            if (transform.position.y < -10) Respawn();
        }

        public void Respawn()
        {
            body.enabled = false;
            transform.position = new Vector3(0, .15f, -5);
            body.enabled = true;
            initialized = false; wasContact = false; velocity = pushVelocity = Vector3.zero;
        }
    }
}
