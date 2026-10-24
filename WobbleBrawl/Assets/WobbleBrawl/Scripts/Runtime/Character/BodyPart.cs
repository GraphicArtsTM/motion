using System.Collections.Generic;
using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>One rigid segment of a fighter. Forwards collisions to its owner for damage and sound.</summary>
    public sealed class BodyPart : MonoBehaviour
    {
        public Brawler owner;
        public PartKind kind;
        public Rigidbody rb;

        [System.NonSerialized] public AttackKind attack;
        [System.NonSerialized] public readonly HashSet<Brawler> struck = new HashSet<Brawler>();

        public void BeginAttack(AttackKind kind)
        {
            attack = kind;
            struck.Clear();
        }

        public void EndAttack() => attack = AttackKind.None;

        void OnCollisionEnter(Collision c)
        {
            if (owner != null) owner.OnPartCollision(this, c);
        }
    }
}
