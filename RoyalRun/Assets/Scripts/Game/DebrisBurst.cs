using UnityEngine;

// A small burst made of a few tiny cubes that fly apart and shrink.
//   Spawn(...)   - dust and splinters when an obstacle hits something (falls with gravity);
//   Sparkle(...) - glittering sparks when a coin, gem or power-up is picked up (float up and spin).
public class DebrisBurst : MonoBehaviour
{
    Transform[] parts;
    Vector3[] velocities;
    float life;
    float gravityScale;
    float size;
    float age;

    public static void Spawn(Vector3 position, Color color, Transform parent)
    {
        Create(position, color, parent, 7, 0.6f, 1f, 0.14f, 3f, 2f, 0f);
    }

    // A big break: planks, stones or splinters flying in all directions (a hazard the hero smashed).
    public static void Shatter(Vector3 position, Color color, Transform parent)
    {
        Create(position, color, parent, 16, 1.1f, 1f, 0.24f, 4.5f, 3.5f, 0f);
    }

    // A small puff of dust under a running foot.
    public static void Dust(Vector3 position, Color color, Transform parent)
    {
        Create(position, color, parent, 3, 0.4f, 0.25f, 0.11f, 0.9f, 0.6f, 0f);
    }

    public static void Sparkle(Vector3 position, Color color, Transform parent, int pieces = 8)
    {
        Create(position, color, parent, pieces, 0.45f, -0.15f, 0.12f, 2.6f, 1.2f, 1.6f);
    }

    static void Create(Vector3 position, Color color, Transform parent, int pieces, float life,
                       float gravityScale, float size, float spread, float up, float emission)
    {
        GameObject go = new GameObject("Burst");
        go.transform.SetParent(parent, true);
        go.transform.position = position;
        DebrisBurst d = go.AddComponent<DebrisBurst>();
        d.life = life;
        d.gravityScale = gravityScale;
        d.size = size;
        d.parts = new Transform[pieces];
        d.velocities = new Vector3[pieces];
        for (int i = 0; i < pieces; i++)
        {
            GameObject p = MatLib.Prim(PrimitiveType.Cube, "Piece", go.transform, Vector3.zero,
                                       Vector3.one * size, color, false, Random.rotation.eulerAngles, 0.6f, emission);
            p.GetComponent<Renderer>().shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            d.parts[i] = p.transform;
            Vector3 v = Random.insideUnitSphere * spread;
            v.y = Mathf.Abs(v.y) + up;
            d.velocities[i] = v;
        }
    }

    void Update()
    {
        float dt = Time.deltaTime;
        age += dt;
        float k = 1f - Mathf.Clamp01(age / life);
        for (int i = 0; i < parts.Length; i++)
        {
            velocities[i] += Physics.gravity * (gravityScale * dt);
            velocities[i] *= 1f - 2f * dt;        // a little air drag
            parts[i].localPosition += velocities[i] * dt;
            parts[i].localScale = Vector3.one * size * k;
            parts[i].Rotate(400f * dt, 300f * dt, 0f, Space.Self);
        }
        if (age >= life) Destroy(gameObject);
    }
}
