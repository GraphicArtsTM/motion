using UnityEngine;

// A small "dust and splinters" effect made of a few tiny cubes that fly apart and shrink.
// Used by Rock when no ParticleSystem is assigned.
public class DebrisBurst : MonoBehaviour
{
    const int Pieces = 7;
    const float Life = 0.6f;

    Transform[] parts;
    Vector3[] velocities;
    float age;

    public static void Spawn(Vector3 position, Color color, Transform parent)
    {
        GameObject go = new GameObject("Debris");
        go.transform.SetParent(parent, true);
        go.transform.position = position;
        DebrisBurst d = go.AddComponent<DebrisBurst>();
        d.parts = new Transform[Pieces];
        d.velocities = new Vector3[Pieces];
        for (int i = 0; i < Pieces; i++)
        {
            GameObject p = MatLib.Prim(PrimitiveType.Cube, "Piece", go.transform, Vector3.zero,
                                       Vector3.one * Random.Range(0.08f, 0.18f), color, false, Random.rotation.eulerAngles);
            d.parts[i] = p.transform;
            Vector3 v = Random.insideUnitSphere * 3f;
            v.y = Mathf.Abs(v.y) + 2f;
            d.velocities[i] = v;
        }
    }

    void Update()
    {
        float dt = Time.deltaTime;
        age += dt;
        float k = 1f - Mathf.Clamp01(age / Life);
        for (int i = 0; i < parts.Length; i++)
        {
            velocities[i] += Physics.gravity * dt;
            parts[i].localPosition += velocities[i] * dt;
            parts[i].localScale = Vector3.one * 0.14f * k;
        }
        if (age >= Life) Destroy(gameObject);
    }
}
