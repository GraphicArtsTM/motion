using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

// Merges all the small shapes of a template into one mesh per material.
// A road piece made of 80 cubes and spheres turns into ~10 meshes, so the game can show
// detailed scenery (trees, towers, flowers, banners) without losing frames.
// Colliders are kept: only the renderers are merged.
public static class MeshBaker
{
    // Phones: shapes with plain colours are re-packed into the shared palette materials (ShapeBuilder.PaletteLib),
    // so a whole road piece is drawn with a handful of draw calls. Textured surfaces (cobbles, grass, bricks,
    // stone, wood, bark) keep their own materials.
    public static bool Palette;

    static readonly Dictionary<string, Mesh> paletteMeshes = new Dictionary<string, Mesh>();

    static bool KeepsTexture(Surface s)
    {
        return s == Surface.Road || s == Surface.Grass || s == Surface.Bricks || s == Surface.Stone
               || s == Surface.Wood || s == Surface.Bark;
    }

    // A copy of the mesh whose every UV points at the colour's palette cell.
    static Mesh PaletteMesh(Mesh source, Color color)
    {
        string key = source.GetInstanceID() + "|" + ColorUtility.ToHtmlStringRGB(color);
        Mesh m;
        if (paletteMeshes.TryGetValue(key, out m) && m != null) return m;
        m = Object.Instantiate(source);
        m.name = source.name + " pal";
        Vector2 uv = PaletteLib.UV(color);
        Vector2[] uvs = new Vector2[m.vertexCount];
        for (int i = 0; i < uvs.Length; i++) uvs[i] = uv;
        m.uv = uvs;
        paletteMeshes[key] = m;
        return m;
    }

    public static void Bake(GameObject root)
    {
        MeshRenderer[] renderers = root.GetComponentsInChildren<MeshRenderer>(true);
        Dictionary<Material, List<CombineInstance>> groups = new Dictionary<Material, List<CombineInstance>>();
        Dictionary<Material, int> vertexCounts = new Dictionary<Material, int>();
        List<MeshRenderer> merged = new List<MeshRenderer>();
        Matrix4x4 toRoot = root.transform.worldToLocalMatrix;

        foreach (MeshRenderer r in renderers)
        {
            MeshFilter mf = r.GetComponent<MeshFilter>();
            Material mat = r.sharedMaterial;
            // a mesh that cannot be read on this platform is simply left as it is
            if (mf == null || mf.sharedMesh == null || mat == null || !mf.sharedMesh.isReadable) continue;
            // a mesh with several materials (ShapeBuilder) is already one draw call per material
            if (mf.sharedMesh.subMeshCount > 1) continue;
            // moving parts (windmill sails) keep their own renderers
            if (r.GetComponentInParent<NoBake>(true) != null) continue;

            Mesh source = mf.sharedMesh;
            MatLib.Info info;
            if (Palette && MatLib.TryInfo(mat, out info) && !KeepsTexture(info.surface))
            {
                source = PaletteMesh(source, info.color);
                mat = PaletteLib.Material(info.emission >= 0.3f ? ShapeBuilder.Glow
                                          : info.smoothness >= 0.55f || info.surface == Surface.Metal ? ShapeBuilder.Shiny
                                          : ShapeBuilder.Matte);
            }

            List<CombineInstance> list;
            if (!groups.TryGetValue(mat, out list))
            {
                list = new List<CombineInstance>();
                groups[mat] = list;
                vertexCounts[mat] = 0;
            }
            list.Add(new CombineInstance
            {
                mesh = source,
                subMeshIndex = 0,
                transform = toRoot * r.transform.localToWorldMatrix,
            });
            vertexCounts[mat] += source.vertexCount;
            merged.Add(r);
        }

        if (merged.Count < 2 && !Palette) return;
        if (Palette) PaletteLib.Flush();

        foreach (KeyValuePair<Material, List<CombineInstance>> g in groups)
        {
            Mesh mesh = new Mesh();
            mesh.name = "Baked " + root.name;
            if (vertexCounts[g.Key] > 65000) mesh.indexFormat = IndexFormat.UInt32;
            mesh.CombineMeshes(g.Value.ToArray(), true, true);
            mesh.RecalculateBounds();

            GameObject go = new GameObject("Baked Mesh");
            go.transform.SetParent(root.transform, false);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            MeshRenderer mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = g.Key;
            // the ground and the road never cast a shadow on anything: skip them in the shadow pass
            MatLib.Info gi;
            if (MatLib.TryInfo(g.Key, out gi) && (gi.surface == Surface.Grass || gi.surface == Surface.Road))
                mr.shadowCastingMode = ShadowCastingMode.Off;
        }

        // remove the old renderers; empty objects without colliders or scripts are deleted.
        // Children come after their parents in the list, so we walk it backwards.
        for (int i = merged.Count - 1; i >= 0; i--)
        {
            MeshRenderer r = merged[i];
            if (r == null) continue;
            GameObject go = r.gameObject;
            MeshFilter mf = go.GetComponent<MeshFilter>();
            Object.DestroyImmediate(r);
            if (mf != null) Object.DestroyImmediate(mf);

            if (go != root && go.transform.childCount == 0 && go.GetComponents<Component>().Length == 1)
                Object.DestroyImmediate(go);
        }
    }
}
