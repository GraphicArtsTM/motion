using UnityEngine;

// The ad (sponsor) flag under the rocket. It draws a cloth strip with a picture and waves it.
// Put it on an empty child object of the rocket (the Player Rocket prefab).
// From the ads guide, Part 12.4.
[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public class AdFlag : MonoBehaviour
{
    [Header("Picture and material")]
    [SerializeField] Texture adTexture;
    [SerializeField] Material flagMaterial;

    [Header("Flag size (in scene units)")]
    [SerializeField] float width = 0.7f;
    [SerializeField] float height = 1.4f;
    [SerializeField] int segments = 16;

    [Header("Waving")]
    [SerializeField] float idleWave = 0.08f;     // waving when the rocket stands still
    [SerializeField] float flightWave = 0.25f;   // waving at speed
    [SerializeField] float waveSpeed = 6f;
    [SerializeField] float waveLength = 1.0f;
    [SerializeField] float trailStrength = 0.08f; // how much the flag falls behind the movement

    Mesh mesh;
    Vector3[] baseVerts;
    Vector3[] verts;
    Rigidbody body;
    Vector3 smoothVelocity;

    void Awake()
    {
        body = GetComponentInParent<Rigidbody>();
        BuildMesh();
        ApplyMaterial();
    }

    void BuildMesh()
    {
        segments = Mathf.Max(2, segments);
        int rows = segments + 1;
        baseVerts = new Vector3[rows * 2];
        verts = new Vector3[rows * 2];
        Vector2[] uv = new Vector2[rows * 2];

        for (int i = 0; i < rows; i++)
        {
            float t = i / (float)segments; // 0 - at the rocket, 1 - the end of the flag
            baseVerts[i * 2] = new Vector3(-width / 2f, -t * height, 0f);
            baseVerts[i * 2 + 1] = new Vector3(width / 2f, -t * height, 0f);
            uv[i * 2] = new Vector2(0f, 1f - t);
            uv[i * 2 + 1] = new Vector2(1f, 1f - t);
        }

        // Triangles on both sides, so the flag can be seen from the "back" too
        int[] tris = new int[segments * 12];
        int k = 0;
        for (int i = 0; i < segments; i++)
        {
            int a = i * 2, b = a + 1, c = a + 2, d = a + 3;
            tris[k++] = a; tris[k++] = c; tris[k++] = b;
            tris[k++] = b; tris[k++] = c; tris[k++] = d;
            tris[k++] = a; tris[k++] = b; tris[k++] = c;
            tris[k++] = b; tris[k++] = d; tris[k++] = c;
        }

        mesh = new Mesh();
        mesh.name = "AdFlagMesh";
        mesh.MarkDynamic();
        mesh.vertices = baseVerts;
        mesh.uv = uv;
        mesh.triangles = tris;
        mesh.RecalculateBounds();
        GetComponent<MeshFilter>().sharedMesh = mesh;
    }

    void ApplyMaterial()
    {
        Material m = flagMaterial;
        if (m == null)
        {
            Shader sh = Shader.Find("Universal Render Pipeline/Unlit");
            if (sh == null) sh = Shader.Find("Unlit/Texture");
            m = new Material(sh);
        }
        else
        {
            m = new Material(m); // our own copy, so we do not change the material file
        }
        if (adTexture != null)
        {
            if (m.HasProperty("_BaseMap")) m.SetTexture("_BaseMap", adTexture);
            if (m.HasProperty("_MainTex")) m.SetTexture("_MainTex", adTexture);
        }
        MeshRenderer r = GetComponent<MeshRenderer>();
        r.sharedMaterial = m;
        r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        r.receiveShadows = false;
    }

    void LateUpdate()
    {
        // The flag always hangs "down", even when the rocket is tilted
        transform.rotation = Quaternion.identity;
        if (transform.parent != null)
        {
            Vector3 ps = transform.parent.lossyScale;
            transform.localScale = new Vector3(1f / Mathf.Max(0.0001f, ps.x),
                                               1f / Mathf.Max(0.0001f, ps.y),
                                               1f / Mathf.Max(0.0001f, ps.z));
        }

        Vector3 vel = body != null ? body.linearVelocity : Vector3.zero;
        smoothVelocity = Vector3.Lerp(smoothVelocity, vel, 6f * Time.deltaTime);
        float speed01 = Mathf.Clamp01(smoothVelocity.magnitude / 8f);
        float amp = Mathf.Lerp(idleWave, flightWave, speed01);

        for (int i = 0; i < baseVerts.Length; i++)
        {
            Vector3 v = baseVerts[i];
            float t = -v.y / height; // 0..1 along the flag
            float phase = Time.time * waveSpeed - (-v.y) * (Mathf.PI * 2f / waveLength);
            float side = (i % 2 == 0) ? 0f : 0.6f; // the edges wave a little differently
            // The farther from the rocket, the stronger the waving (the cloth is fixed at the rocket)
            v.x += Mathf.Sin(phase + side) * amp * t;
            v.z += Mathf.Cos(phase) * amp * 0.5f * t;
            // The flag falls behind the movement: most of all at the free end
            v.x -= smoothVelocity.x * trailStrength * t * t;
            v.y -= smoothVelocity.y * trailStrength * t * t;
            verts[i] = v;
        }
        mesh.vertices = verts;
        mesh.RecalculateBounds();
    }

    // Hides the flag (for example, at the moment of the explosion)
    public void Hide()
    {
        GetComponent<MeshRenderer>().enabled = false;
    }

    void OnDrawGizmosSelected()
    {
        // A frame in the editor: it shows where the flag will hang
        Gizmos.color = Color.yellow;
        Vector3 p = transform.position;
        Gizmos.DrawWireCube(p + Vector3.down * (height / 2f), new Vector3(width, height, 0.05f));
    }
}
