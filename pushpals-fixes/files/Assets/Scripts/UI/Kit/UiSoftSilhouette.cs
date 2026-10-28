using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace PushPals.UI
{
    /// <summary>
    /// Мягкая тень-силуэт без своего шейдера и без чтения текстур: картинка рисуется копиями со сдвигами по двум
    /// кругам (радиус Radius) — край выходит размытым. Цвет и плотность берутся у самой картинки (Image.color):
    /// столько выходит там, где силуэт сплошной. Тени предметов главного меню, ярлыков и логотипа.
    /// </summary>
    [RequireComponent(typeof(Graphic))]
    public class UiSoftSilhouette : BaseMeshEffect
    {
        [Tooltip("Насколько размыт край (в единицах интерфейса)")]
        [SerializeField] private float radius = 8f;

        // Середина, 6 копий на половине радиуса, 8 — на радиусе
        private static readonly Vector2[] Offsets = MakeOffsets();
        private static readonly List<UIVertex> source = new List<UIVertex>();
        private static readonly List<UIVertex> result = new List<UIVertex>();

        public float Radius
        {
            get => radius;
            set
            {
                if (Mathf.Approximately(radius, value)) return;
                radius = value;
                if (graphic != null) graphic.SetVerticesDirty();
            }
        }

        public override void ModifyMesh(VertexHelper vh)
        {
            if (!IsActive() || vh.currentVertCount == 0) return;
            source.Clear();
            vh.GetUIVertexStream(source);
            result.Clear();
            int n = Offsets.Length;
            for (int k = 0; k < n; k++)
            {
                Vector3 shift = Offsets[k] * radius;
                for (int i = 0; i < source.Count; i++)
                {
                    var v = source[i];
                    v.position += shift;
                    // Копии накладываются: каждой — столько, чтобы вместе вышла прозрачность картинки
                    var c = v.color;
                    c.a = (byte)Mathf.RoundToInt(255f * (1f - Mathf.Pow(1f - c.a / 255f, 1f / n)));
                    v.color = c;
                    result.Add(v);
                }
            }
            vh.Clear();
            vh.AddUIVertexTriangleStream(result);
        }

        private static Vector2[] MakeOffsets()
        {
            var list = new List<Vector2> { Vector2.zero };
            for (int i = 0; i < 6; i++)
            {
                float a = i * Mathf.PI / 3f;
                list.Add(new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * 0.5f);
            }
            for (int i = 0; i < 8; i++)
            {
                float a = i * Mathf.PI / 4f + 0.39f;
                list.Add(new Vector2(Mathf.Cos(a), Mathf.Sin(a)));
            }
            return list.ToArray();
        }
    }
}
