using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>
    /// A ConfigurableJoint used as a motorised muscle. All body parts are built in a rest pose with
    /// identity relative rotations, so a desired rotation of the child relative to its parent maps
    /// to <c>targetRotation = Inverse(desired)</c>.
    /// </summary>
    public sealed class Muscle
    {
        public readonly ConfigurableJoint joint;
        public readonly Rigidbody body;
        public readonly Rigidbody parent;
        readonly float spring, damper;
        float strength = -1f;

        public Muscle(ConfigurableJoint joint, Vector2 springDamper)
        {
            this.joint = joint;
            body = joint.GetComponent<Rigidbody>();
            parent = joint.connectedBody;
            spring = springDamper.x;
            damper = springDamper.y;
            SetStrength(1f);
        }

        /// <summary>Desired rotation of the child expressed in the parent's frame.</summary>
        public void SetTarget(Quaternion relativeToParent)
        {
            joint.targetRotation = Quaternion.Inverse(relativeToParent);
        }

        public void SetStrength(float s)
        {
            if (Mathf.Abs(s - strength) < 0.015f) return;
            strength = s;
            joint.slerpDrive = new JointDrive
            {
                positionSpring = spring * s,
                positionDamper = damper * Mathf.Max(s, 0.15f),
                maximumForce = float.MaxValue,
            };
        }

        public static Quaternion Flex(float forwardDeg) => Quaternion.AngleAxis(-forwardDeg, Vector3.right);
        public static Quaternion Bend(float backwardDeg) => Quaternion.AngleAxis(backwardDeg, Vector3.right);
    }
}
