using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>Googly eyes, blinking, squinting when hurt, X-eyes and orbiting stars when knocked out.</summary>
    public sealed class BrawlerFace : MonoBehaviour
    {
        Brawler owner;
        Transform head;
        Rigidbody headRb;
        Transform eyeL, eyeR, pupilL, pupilR, crossL, crossR, mouth;
        Transform starRoot;
        Transform[] stars;
        Vector3 pupilOffset, pupilVel;
        float blinkTimer, blinkLeft, hurtTimer;
        static readonly Color White = new Color(0.97f, 0.97f, 0.97f);
        static readonly Color Black = new Color(0.05f, 0.05f, 0.07f);

        public static BrawlerFace Create(Brawler owner, Transform head, Color skin)
        {
            var f = head.gameObject.AddComponent<BrawlerFace>();
            f.owner = owner;
            f.head = head;
            f.headRb = head.GetComponent<Rigidbody>();
            f.eyeL = Kit.Deco(PrimitiveType.Sphere, head, new Vector3(-0.095f, 0.05f, 0.19f), new Vector3(0.13f, 0.15f, 0.08f), White, null, false, 0.6f).transform;
            f.eyeR = Kit.Deco(PrimitiveType.Sphere, head, new Vector3(0.095f, 0.05f, 0.19f), new Vector3(0.13f, 0.15f, 0.08f), White, null, false, 0.6f).transform;
            f.pupilL = Kit.Deco(PrimitiveType.Sphere, head, new Vector3(-0.095f, 0.05f, 0.226f), Vector3.one * 0.06f, Black, null, false, 0.8f).transform;
            f.pupilR = Kit.Deco(PrimitiveType.Sphere, head, new Vector3(0.095f, 0.05f, 0.226f), Vector3.one * 0.06f, Black, null, false, 0.8f).transform;
            f.crossL = MakeCross(head, new Vector3(-0.095f, 0.05f, 0.235f));
            f.crossR = MakeCross(head, new Vector3(0.095f, 0.05f, 0.235f));
            f.mouth = Kit.Deco(PrimitiveType.Sphere, head, new Vector3(0, -0.09f, 0.205f), new Vector3(0.11f, 0.03f, 0.05f), Palette.Darken(skin, 0.3f), null, false).transform;

            f.starRoot = new GameObject("KO_Stars").transform;
            f.starRoot.SetParent(owner.transform, false);
            f.stars = new Transform[3];
            for (int i = 0; i < 3; i++)
                f.stars[i] = Kit.Deco(PrimitiveType.Sphere, f.starRoot, Vector3.zero, Vector3.one * 0.11f, new Color(1f, 0.9f, 0.2f), null, false, 0.6f, 1.5f).transform;
            f.starRoot.gameObject.SetActive(false);
            f.blinkTimer = Random.Range(1f, 4f);
            return f;
        }

        static Transform MakeCross(Transform head, Vector3 pos)
        {
            var root = new GameObject("Cross").transform;
            root.SetParent(head, false);
            root.localPosition = pos;
            Kit.Deco(PrimitiveType.Cube, root, Vector3.zero, new Vector3(0.12f, 0.025f, 0.02f), Black, Quaternion.Euler(0, 0, 45), false);
            Kit.Deco(PrimitiveType.Cube, root, Vector3.zero, new Vector3(0.12f, 0.025f, 0.02f), Black, Quaternion.Euler(0, 0, -45), false);
            root.gameObject.SetActive(false);
            return root;
        }

        public void Hurt() => hurtTimer = 0.45f;

        void LateUpdate()
        {
            if (owner == null) return;
            float dt = Time.deltaTime;
            bool ko = owner.IsKnockedOut || owner.IsOut;

            crossL.gameObject.SetActive(ko);
            crossR.gameObject.SetActive(ko);
            pupilL.gameObject.SetActive(!ko);
            pupilR.gameObject.SetActive(!ko);
            eyeL.gameObject.SetActive(!ko);
            eyeR.gameObject.SetActive(!ko);

            // blink
            blinkTimer -= dt;
            if (blinkTimer <= 0f) { blinkLeft = 0.12f; blinkTimer = Random.Range(2f, 5f); }
            if (blinkLeft > 0f) blinkLeft -= dt;
            if (hurtTimer > 0f) hurtTimer -= dt;
            float openY = blinkLeft > 0f ? 0.02f : hurtTimer > 0f ? 0.06f : 0.15f;
            var s = eyeL.localScale;
            s.y = Mathf.Lerp(s.y, openY, 30f * dt);
            eyeL.localScale = s;
            eyeR.localScale = s;

            // googly pupils: a damped spring pushed around by the head's motion
            if (headRb != null)
            {
                Vector3 localVel = head.InverseTransformDirection(headRb.linearVelocity);
                Vector3 force = -pupilOffset * 260f - pupilVel * 9f - new Vector3(localVel.x, localVel.y, 0) * 2.2f;
                pupilVel += force * dt;
                pupilOffset += pupilVel * dt;
                pupilOffset.z = 0;
                pupilOffset = Vector3.ClampMagnitude(pupilOffset, 0.03f);
            }
            float look = owner.IsHeldByOthers ? 0.02f : 0f;
            pupilL.localPosition = new Vector3(-0.095f, 0.05f, 0.226f) + pupilOffset + new Vector3(look, 0, 0);
            pupilR.localPosition = new Vector3(0.095f, 0.05f, 0.226f) + pupilOffset - new Vector3(look, 0, 0);
            pupilL.gameObject.SetActive(!ko && blinkLeft <= 0f);
            pupilR.gameObject.SetActive(!ko && blinkLeft <= 0f);

            // mouth opens when hurt or knocked out
            float mouthOpen = ko ? 0.07f : hurtTimer > 0f ? 0.08f : owner.IsStraining ? 0.05f : 0.03f;
            var ms = mouth.localScale;
            ms.y = Mathf.Lerp(ms.y, mouthOpen, 20f * dt);
            mouth.localScale = ms;

            // KO stars
            starRoot.gameObject.SetActive(owner.IsKnockedOut);
            if (owner.IsKnockedOut)
            {
                starRoot.position = head.position + Vector3.up * 0.42f;
                float t = Time.time * 4f;
                for (int i = 0; i < stars.Length; i++)
                {
                    float a = t + i * Mathf.PI * 2f / stars.Length;
                    stars[i].localPosition = new Vector3(Mathf.Cos(a) * 0.3f, Mathf.Sin(a * 2f) * 0.04f, Mathf.Sin(a) * 0.3f);
                }
            }
        }
    }
}
