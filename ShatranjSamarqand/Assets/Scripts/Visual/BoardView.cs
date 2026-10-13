using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using Shatranj.Chess;

namespace Shatranj.Visual
{
    public enum BattleStyle { Full, Fast, Off }

    /// <summary>
    /// Доска (паркет из чинары и ореха, рама с ислими, золотая инкрустация), подсветки
    /// и все 3D-фигуры. Отвечает за анимацию ходов и сабельных поединков.
    /// </summary>
    public class BoardView : MonoBehaviour
    {
        public static Vector3 SquarePos(int sq) { return new Vector3(Sq.File(sq) - 3.5f, 0f, Sq.Rank(sq) - 3.5f); }

        public static int SquareAt(Vector3 p)
        {
            int f = Mathf.FloorToInt(p.x + 4f), r = Mathf.FloorToInt(p.z + 4f);
            return Sq.OnBoard(f, r) ? Sq.Make(f, r) : -1;
        }

        public Action OnFootstep;
        public Action OnWhoosh;
        public Action OnImpact;
        public Action OnPromote;
        public Action<PieceView> OnHero;
        public CameraRig Rig;

        Transform piecesRoot, hlRoot, coordsRoot;
        readonly Dictionary<int, PieceView> views = new Dictionary<int, PieceView>();
        readonly List<Transform> hlPool = new List<Transform>();
        int hlUsed;
        Material matDot, matRing, matSelect, matLast, matCheck;
        Transform checkMarker;

        public IEnumerable<PieceView> Views { get { return views.Values; } }

        // ------------------------------------------------------------------ Построение доски

        public void Build()
        {
            piecesRoot = new GameObject("Pieces").transform;
            piecesRoot.SetParent(transform, false);
            hlRoot = new GameObject("Highlights").transform;
            hlRoot.SetParent(transform, false);

            var boardRoot = new GameObject("Board").transform;
            boardRoot.SetParent(transform, false);

            // основание
            AddBox(boardRoot, MaterialLib.FrameWood, new Vector3(0, -0.17f, 0), new Vector3(9.7f, 0.32f, 9.7f));
            // рама с орнаментом
            var frameMat = new Material(MaterialLib.Frame) { mainTextureScale = new Vector2(3.3f, 1f) };
            for (int i = 0; i < 4; i++)
            {
                var t = AddBox(boardRoot, frameMat, Vector3.zero, new Vector3(8.16f, 0.1f, 0.62f));
                t.localRotation = Quaternion.Euler(0, 90f * i, 0);
                t.localPosition = t.localRotation * new Vector3(0, -0.04f, -4.39f);
            }
            for (int i = 0; i < 4; i++)
            {
                float x = (i % 2 == 0 ? 1 : -1) * 4.39f, z = (i < 2 ? 1 : -1) * 4.39f;
                AddBox(boardRoot, MaterialLib.FrameWood, new Vector3(x, -0.04f, z), new Vector3(0.62f, 0.1f, 0.62f));
                var star = Part(boardRoot, MeshBuilder.Cached("lathe.rosette", () => MeshBuilder.Lathe("rosette", new[]
                {
                    new Vector2(0, 0), new Vector2(0.24f, 0), new Vector2(0.24f, 0.012f), new Vector2(0.12f, 0.03f), new Vector2(0, 0.035f)
                }, 8, 22.5f, 360f, true)), MaterialLib.Inlay, new Vector3(x, 0.011f, z));
                star.localRotation = Quaternion.Euler(0, 22.5f, 0);
            }
            // золотая инкрустация вокруг поля
            for (int i = 0; i < 4; i++)
            {
                var t = AddBox(boardRoot, MaterialLib.Inlay, Vector3.zero, new Vector3(8.14f, 0.03f, 0.05f));
                t.localRotation = Quaternion.Euler(0, 90f * i, 0);
                t.localPosition = t.localRotation * new Vector3(0, 0.0f, -4.045f);
            }

            // клетки
            BuildSquares(boardRoot, true);
            BuildSquares(boardRoot, false);

            var col = boardRoot.gameObject.AddComponent<BoxCollider>();
            col.center = new Vector3(0, -0.17f, 0);
            col.size = new Vector3(9.7f, 0.34f, 9.7f);

            BuildCoordinates();

            matDot = MaterialLib.Unlit(new Color(1f, 0.86f, 0.35f, 0.85f), TextureFactory.Circle());
            matRing = MaterialLib.Unlit(new Color(1f, 0.3f, 0.2f, 0.9f), TextureFactory.Ring(128, 0.14f));
            matSelect = MaterialLib.Unlit(new Color(1f, 0.85f, 0.3f, 0.5f), TextureFactory.SoftSquare());
            matLast = MaterialLib.Unlit(new Color(0.35f, 0.8f, 1f, 0.3f), TextureFactory.SoftSquare());
            matCheck = MaterialLib.Unlit(new Color(1f, 0.12f, 0.08f, 0.8f), TextureFactory.Glow());
        }

        static Transform AddBox(Transform parent, Material m, Vector3 pos, Vector3 size)
        {
            var t = Part(parent, MeshBuilder.Cube, m, pos);
            t.localScale = size;
            return t;
        }

        static Transform Part(Transform parent, Mesh mesh, Material m, Vector3 pos)
        {
            var go = new GameObject(mesh.name);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            go.AddComponent<MeshRenderer>().sharedMaterial = m;
            return go.transform;
        }

        void BuildSquares(Transform parent, bool light)
        {
            var verts = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            var rng = new System.Random(light ? 17 : 29);
            for (int sq = 0; sq < 64; sq++)
            {
                if (Sq.IsLight(sq) != light) continue;
                Vector3 c = SquarePos(sq);
                int i0 = verts.Count;
                verts.Add(c + new Vector3(-0.5f, 0, -0.5f));
                verts.Add(c + new Vector3(-0.5f, 0, 0.5f));
                verts.Add(c + new Vector3(0.5f, 0, 0.5f));
                verts.Add(c + new Vector3(0.5f, 0, -0.5f));
                // у каждой клетки свой кусок древесины, волокна чередуются как в паркете
                float ou = (float)rng.NextDouble(), ov = (float)rng.NextDouble();
                const float s = 0.45f;
                bool rot = ((Sq.File(sq) + Sq.Rank(sq) / 2) & 1) == 0;
                Vector2 a = new Vector2(ou, ov), b = new Vector2(ou, ov + s), cc = new Vector2(ou + s, ov + s), d = new Vector2(ou + s, ov);
                if (rot) { uvs.Add(b); uvs.Add(cc); uvs.Add(d); uvs.Add(a); }
                else { uvs.Add(a); uvs.Add(b); uvs.Add(cc); uvs.Add(d); }
                tris.Add(i0); tris.Add(i0 + 1); tris.Add(i0 + 2);
                tris.Add(i0); tris.Add(i0 + 2); tris.Add(i0 + 3);
            }
            var m = new Mesh { name = light ? "squares.light" : "squares.dark" };
            m.SetVertices(verts);
            m.SetUVs(0, uvs);
            m.SetTriangles(tris, 0);
            m.RecalculateNormals();
            m.RecalculateBounds();
            Part(parent, m, light ? MaterialLib.BoardLight : MaterialLib.BoardDark, Vector3.zero);
        }

        void BuildCoordinates()
        {
            coordsRoot = new GameObject("Coordinates").transform;
            coordsRoot.SetParent(transform, false);
            Font font = UI.UIKit.DefaultFont;
            if (font == null) return;
            for (int i = 0; i < 8; i++)
            {
                string file = ((char)('a' + i)).ToString();
                string rank = (i + 1).ToString();
                AddLabel(font, file, new Vector3(i - 3.5f, 0.016f, -4.39f), 0f);
                AddLabel(font, file, new Vector3(i - 3.5f, 0.016f, 4.39f), 180f);
                AddLabel(font, rank, new Vector3(-4.39f, 0.016f, i - 3.5f), 0f);
                AddLabel(font, rank, new Vector3(4.39f, 0.016f, i - 3.5f), 180f);
            }
        }

        void AddLabel(Font font, string text, Vector3 pos, float yaw)
        {
            var go = new GameObject("coord_" + text);
            go.transform.SetParent(coordsRoot, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = Quaternion.Euler(90, yaw, 0);
            var tm = go.AddComponent<TextMesh>();
            tm.font = font;
            tm.text = text;
            tm.fontSize = 64;
            tm.characterSize = 0.055f;
            tm.anchor = TextAnchor.MiddleCenter;
            tm.alignment = TextAlignment.Center;
            tm.fontStyle = FontStyle.Bold;
            tm.color = new Color(1f, 0.93f, 0.75f);
            var mr = go.GetComponent<MeshRenderer>();
            mr.sharedMaterial = font.material;
            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        }

        public void SetCoordinatesVisible(bool on)
        {
            if (coordsRoot != null) coordsRoot.gameObject.SetActive(on);
        }

        // ------------------------------------------------------------------ Подсветки

        Transform NextHighlight(Material m, Vector3 pos, float size, float yOffset)
        {
            Transform t;
            if (hlUsed < hlPool.Count) t = hlPool[hlUsed];
            else
            {
                var go = new GameObject("hl");
                go.transform.SetParent(hlRoot, false);
                go.AddComponent<MeshFilter>().sharedMesh = MeshBuilder.QuadXZ;
                var r = go.AddComponent<MeshRenderer>();
                r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                r.receiveShadows = false;
                t = go.transform;
                hlPool.Add(t);
            }
            hlUsed++;
            t.gameObject.SetActive(true);
            t.GetComponent<MeshRenderer>().sharedMaterial = m;
            t.localPosition = pos + new Vector3(0, yOffset, 0);
            t.localScale = new Vector3(size, 1, size);
            return t;
        }

        public void ClearHighlights()
        {
            for (int i = 0; i < hlPool.Count; i++) hlPool[i].gameObject.SetActive(false);
            hlUsed = 0;
            checkMarker = null;
        }

        public void ShowLastMove(int from, int to)
        {
            NextHighlight(matLast, SquarePos(from), 1f, 0.004f);
            NextHighlight(matLast, SquarePos(to), 1f, 0.004f);
        }

        public void ShowSelection(int sq, List<Move> moves, bool showMoves)
        {
            NextHighlight(matSelect, SquarePos(sq), 1f, 0.006f);
            if (!showMoves) return;
            var seen = new HashSet<int>();
            foreach (var m in moves)
            {
                if (!seen.Add(m.To)) continue;
                if (m.IsCapture) NextHighlight(matRing, SquarePos(m.To), 0.98f, 0.009f);
                else NextHighlight(matDot, SquarePos(m.To), 0.3f, 0.009f);
            }
        }

        public void ShowCheck(int kingSq)
        {
            checkMarker = NextHighlight(matCheck, SquarePos(kingSq), 1.5f, 0.007f);
        }

        void Update()
        {
            if (checkMarker != null)
            {
                float s = 1.35f + Mathf.Sin(Time.time * 6f) * 0.2f;
                checkMarker.localScale = new Vector3(s, 1, s);
            }
        }

        // ------------------------------------------------------------------ Фигуры

        public PieceView GetView(int id)
        {
            PieceView v;
            return id != 0 && views.TryGetValue(id, out v) ? v : null;
        }

        public PieceView ViewAt(PieceTracker tracker, int sq) { return GetView(tracker.IdAt(sq)); }

        public void ClearPieces()
        {
            foreach (var v in views.Values) if (v != null) Destroy(v.gameObject);
            views.Clear();
        }

        PieceView Spawn(PieceTracker.Info info)
        {
            var v = PieceFactory.Create(Pc.Type(info.Piece), Pc.SideOf(info.Piece), piecesRoot);
            v.Id = info.Id;
            v.transform.position = SquarePos(info.Square);
            v.transform.rotation = Quaternion.Euler(0, v.DefaultYaw, 0);
            v.Kills = info.Kills;
            if (info.Kills >= 3) v.SetHero(true);
            v.OnFootstep = OnFootstep;
            views[info.Id] = v;
            return v;
        }

        public void SpawnAll(PieceTracker tracker)
        {
            ClearPieces();
            foreach (var info in tracker.Alive) Spawn(info);
        }

        /// <summary>Привести фигуры в соответствие с позицией (после отмены хода или загрузки).</summary>
        public void SyncTo(PieceTracker tracker, bool animate)
        {
            var alive = new HashSet<int>();
            foreach (var info in tracker.Alive) alive.Add(info.Id);

            var remove = new List<int>();
            foreach (var kv in views) if (!alive.Contains(kv.Key)) remove.Add(kv.Key);
            foreach (var id in remove)
            {
                var v = views[id];
                views.Remove(id);
                if (v == null) continue;
                if (animate) StartCoroutine(SinkAndDestroy(v));
                else Destroy(v.gameObject);
            }

            foreach (var info in tracker.Alive)
            {
                PieceView v;
                if (views.TryGetValue(info.Id, out v) && v != null && v.Type == Pc.Type(info.Piece) && v.Side == Pc.SideOf(info.Piece))
                {
                    v.StopAllCoroutines();
                    v.ResetPose();
                    v.Kills = info.Kills;
                    v.SetHero(info.Kills >= 3);
                    Vector3 target = SquarePos(info.Square);
                    if (animate) StartCoroutine(Glide(v, target));
                    else
                    {
                        v.transform.position = target;
                        v.transform.rotation = Quaternion.Euler(0, v.DefaultYaw, 0);
                    }
                }
                else
                {
                    if (v != null) Destroy(v.gameObject);
                    var nv = Spawn(info);
                    if (animate) StartCoroutine(Rise(nv));
                }
            }
        }

        IEnumerator Glide(PieceView v, Vector3 target)
        {
            Vector3 from = v.transform.position;
            Quaternion r0 = v.transform.rotation, r1 = Quaternion.Euler(0, v.DefaultYaw, 0);
            for (float t = 0; t < 1f; t += Time.deltaTime / 0.35f)
            {
                if (v == null) yield break;
                float e = Ease.InOut(t);
                v.transform.position = Vector3.Lerp(from, target, e) + Vector3.up * Mathf.Sin(e * Mathf.PI) * 0.15f;
                v.transform.rotation = Quaternion.Slerp(r0, r1, e);
                yield return null;
            }
            if (v == null) yield break;
            v.transform.position = target;
            v.transform.rotation = r1;
        }

        IEnumerator Rise(PieceView v)
        {
            Fx.GoldBurst(v.transform.position + Vector3.up * 0.3f, 25);
            Vector3 target = v.transform.position;
            for (float t = 0; t < 1f; t += Time.deltaTime / 0.4f)
            {
                if (v == null) yield break;
                v.transform.localScale = Vector3.one * Ease.OutBack(t);
                yield return null;
            }
            if (v != null) v.transform.localScale = Vector3.one;
        }

        IEnumerator SinkAndDestroy(PieceView v)
        {
            Vector3 s0 = v.transform.localScale;
            for (float t = 0; t < 1f; t += Time.deltaTime / 0.3f)
            {
                if (v == null) yield break;
                v.transform.localScale = s0 * (1f - Ease.In(t));
                yield return null;
            }
            if (v != null) Destroy(v.gameObject);
        }

        // ------------------------------------------------------------------ Анимация хода

        /// <summary>
        /// Проигрывает ход: прогулка/прыжок, а при взятии — поединок: нападающий подходит,
        /// замахивается, рубит саблей, и деревянная фигура разлетается на части.
        /// </summary>
        public IEnumerator AnimateMove(MoveRecord rec, int moverId, int victimId, int rookId, int moverKillsAfter, BattleStyle style, bool cinematic)
        {
            var mover = GetView(moverId);
            Vector3 dest = SquarePos(rec.Move.To);
            bool leap = Pc.Type(rec.MovedPiece) == PieceType.Knight;
            PieceView victim = victimId != 0 ? GetView(victimId) : null;
            if (victim != null) views.Remove(victimId);

            if (mover == null)
            {
                if (victim != null) Destroy(victim.gameObject);
                yield break;
            }

            PieceView rook = rookId != 0 ? GetView(rookId) : null;

            if (victim != null)
            {
                Vector3 vpos = victim.transform.position;
                Vector3 dir = vpos - mover.transform.position;
                dir.y = 0;
                float dist = dir.magnitude;
                dir = dist > 0.01f ? dir / dist : Vector3.forward;

                if (style == BattleStyle.Off)
                {
                    yield return mover.MoveTo(dest, leap, 3.2f);
                    Vector3 hit = vpos + Vector3.up * 0.4f;
                    Fx.WoodBurst(hit, victim.Side, 25);
                    Fx.Shatter(victim, hit, dir, 0.7f);
                    if (OnImpact != null) OnImpact();
                }
                else
                {
                    bool full = style == BattleStyle.Full;
                    Vector3 approach = dist > 1.3f ? vpos - dir * 0.8f : mover.transform.position;
                    if (full && cinematic && Rig != null) Rig.FocusOn((approach + vpos) * 0.5f + Vector3.up * 0.4f, 0.5f);

                    victim.StartCoroutine(victim.FaceTowards(approach, 0.35f));
                    yield return mover.MoveTo(approach, leap, full ? 2.6f : 3.6f);
                    yield return mover.FaceTowards(vpos, 0.12f);
                    var victimRef = victim;
                    victimRef.StartCoroutine(victimRef.Defend(0.22f));

                    yield return mover.Strike(
                        () => { if (OnWhoosh != null) OnWhoosh(); },
                        () =>
                        {
                            Vector3 hit = vpos + Vector3.up * Mathf.Clamp(victimRef.Height * 0.62f, 0.35f, 0.75f) - dir * 0.15f;
                            Fx.SwordClash(hit);
                            Fx.WoodBurst(hit, victimRef.Side, 45);
                            Fx.Shatter(victimRef, hit, dir, 1f);
                            if (OnImpact != null) OnImpact();
                            if (Rig != null) Rig.Shake(full ? 0.16f : 0.08f, 0.35f);
                            if (full && cinematic) Fx.SlowMo(0.22f, 0.32f);
                        });

                    if (Rig != null) Rig.ReleaseFocus();
                    yield return mover.MoveTo(dest, false, 3f);
                }
            }
            else
            {
                yield return mover.MoveTo(dest, leap);
            }

            // рокировка: Рух обходит Шоха после того, как тот встал на место
            if (rook != null)
            {
                yield return rook.MoveTo(SquarePos(rec.RookTo), false, 2.4f);
                rook.StartCoroutine(rook.FaceDefault(0.25f));
            }

            if (rec.Move.IsPromotion)
            {
                if (OnPromote != null) OnPromote();
                Fx.GoldBurst(dest + Vector3.up * 0.4f, 90);
                yield return SinkAndDestroy(mover);
                var nv = Spawn(new PieceTracker.Info { Id = moverId, Piece = Pc.Make(rec.Mover, rec.Move.Promotion), Square = rec.Move.To, Kills = moverKillsAfter });
                yield return Rise(nv);
                mover = nv;
            }
            else
            {
                yield return mover.FaceDefault(0.25f);
            }

            if (mover != null)
            {
                mover.Kills = moverKillsAfter;
                if (moverKillsAfter >= 3 && !mover.IsHero)
                {
                    mover.SetHero(true);
                    Fx.GoldBurst(mover.transform.position + Vector3.up * 0.5f, 70);
                    if (OnHero != null) OnHero(mover);
                }
            }
        }

        // ------------------------------------------------------------------ Финал

        public IEnumerator PlayFinale(Side? winner, int loserKingId, bool mate)
        {
            if (winner.HasValue)
            {
                var king = GetView(loserKingId);
                if (king != null && mate)
                {
                    PieceView attacker = null;
                    float best = float.MaxValue;
                    foreach (var v in views.Values)
                    {
                        if (v == null || v.Side != winner.Value) continue;
                        float d = Vector3.Distance(v.transform.position, king.transform.position);
                        if (d < best) { best = d; attacker = v; }
                    }
                    Vector3 away = attacker != null ? king.transform.position - attacker.transform.position : Vector3.right;
                    yield return king.Topple(away);
                    views.Remove(loserKingId);
                    Vector3 hit = king.transform.position + Vector3.up * 0.3f;
                    Fx.WoodBurst(hit, king.Side, 60);
                    Fx.Shatter(king, hit, away, 0.6f);
                    if (OnImpact != null) OnImpact();
                    if (Rig != null) Rig.Shake(0.2f, 0.5f);
                }
                foreach (var v in views.Values)
                    if (v != null && v.Side == winner.Value) v.StartCoroutine(v.Cheer(UnityEngine.Random.Range(0f, 0.6f)));
                Fx.Fireworks(new Vector3(0, 0, 0), 14);
            }
            else
            {
                foreach (var v in views.Values)
                    if (v != null) v.StartCoroutine(v.TurnToYaw(v.DefaultYaw + 180f, 0.6f));
            }
            yield return null;
        }
    }
}
