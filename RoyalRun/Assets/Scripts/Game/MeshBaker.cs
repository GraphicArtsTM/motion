using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

// Merges all the small shapes of a template into one mesh per material.
// A road piece made of 80 cubes and spheres turns into ~10 meshes, so the game can show
// detailed scenery (trees, towers, flowers, banners) without losing frames.
// Colliders are kept: only the renderers are merged.
public static class MeshBaker
{
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
            // moving parts (windmill sails) keep their own renderers
            if (r.GetComponentInParent<NoBake>(true) != null) continue;

            List<CombineInstance> list;
            if (!groups.TryGetValue(mat, out list))
            {
                list = new List<CombineInstance>();
                groups[mat] = list;
                vertexCounts[mat] = 0;
            }
            list.Add(new CombineInstance
            {
                mesh = mf.sharedMesh,
                subMeshIndex = 0,
                transform = toRoot * r.transform.localToWorldMatrix,
            });
            vertexCounts[mat] += mf.sharedMesh.vertexCount;
            merged.Add(r);
        }

        if (merged.Count < 2) return;

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
