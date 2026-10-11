using UnityEngine;

namespace PrimalMonke
{
    [RequireComponent(typeof(CharacterController))]
    public sealed class MonkeyBot : MonoBehaviour
    {
        public Transform player;
        public Renderer fur;
        public float speed = 2.5f;
        public bool Tagged { get; private set; }
        public bool Active = true;
        Vector3 home, target;
        CharacterController controller;
        float chooseAt, fallingSpeed;
        void Awake() { controller = GetComponent<CharacterController>(); home = transform.position; }
        public void ResetBot()
        {
            if (controller == null) { controller = GetComponent<CharacterController>(); home = transform.position; }
            controller.enabled = false; transform.position = home; controller.enabled = true;
            Tagged = false; Active = true; chooseAt = 0; fallingSpeed = 0;
            fur.material.color = new Color(.42f, .22f, .12f);
        }
        public void Tag() { Tagged = true; fur.material.color = new Color(1, .42f, .08f); }
        void Update()
        {
            if (!Active || Tagged) return;
            Vector3 away = transform.position - player.position; away.y = 0;
            if (Time.time >= chooseAt)
            {
                Vector2 random = Random.insideUnitCircle * 11;
                target = new Vector3(random.x, 0, random.y);
                if (away.magnitude < 4) target = transform.position + away.normalized * 5;
                target.x = Mathf.Clamp(target.x, -12, 12); target.z = Mathf.Clamp(target.z, -12, 12);
                chooseAt = Time.time + Random.Range(1f, 2.5f);
            }
            Vector3 direction = target - transform.position; direction.y = 0;
            if (direction.magnitude > .5f)
                transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(direction), Time.deltaTime * 5);
            fallingSpeed = controller.isGrounded ? -1 : fallingSpeed + Physics.gravity.y * Time.deltaTime;
            CollisionFlags flags = controller.Move((direction.normalized * speed + Vector3.up * fallingSpeed) * Time.deltaTime);
            if ((flags & CollisionFlags.Sides) != 0) chooseAt = 0;
            if (transform.position.y < -5) ResetBot();
        }
    }
}
