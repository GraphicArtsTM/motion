using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>
    /// A scrappy AI opponent. It chases the most attractive victim, trades punches and kicks,
    /// grabs knocked-out bodies, hauls them to the nearest edge and throws them off — exactly
    /// what a human does in a Gang Beasts match.
    /// </summary>
    public sealed class BotBrain : IBrain
    {
        readonly float skill;
        Brawler target;
        float retarget, punchCd, kickCd, jumpCd, grabPlan, pendingKick = -1f, stuck, mashCd, haulTime;
        Vector3 lastPos, roamPoint;
        float roamTimer;

        static readonly RaycastHit[] hits = new RaycastHit[8];

        public BotBrain(float skill)
        {
            this.skill = Mathf.Clamp(skill, 0.3f, 1.2f);
        }

        public void Think(Brawler self, ref BrawlerCommand cmd, float dt)
        {
            cmd.move = Vector3.zero;
            cmd.jump = false;
            cmd.pitch = 0f;
            if (GameManager.InputLocked)
            {
                cmd.grabL = cmd.grabR = false;
                return;
            }

            punchCd -= dt; kickCd -= dt; jumpCd -= dt; retarget -= dt; mashCd -= dt; roamTimer -= dt;
            var gm = GameManager.I;
            var arena = gm != null ? gm.Arena : null;
            Vector3 pos = self.Position;
            Vector3 center = arena != null ? arena.Center : Vector3.zero;

            if (self.IsKnockedOut)
            {
                cmd.grabL = cmd.grabR = false;
                if (mashCd <= 0f) { cmd.jumpPressed = true; mashCd = Random.Range(0.12f, 0.35f) / skill; }
                return;
            }

            if (self.IsHeldByOthers)
            {
                cmd.grabL = cmd.grabR = false;
                if (mashCd <= 0f)
                {
                    if (Random.value < 0.5f) cmd.jumpPressed = true; else cmd.punchPressed = true;
                    mashCd = Random.Range(0.1f, 0.3f) / skill;
                }
                cmd.move = Random.insideUnitSphere;
                return;
            }

            if (pendingKick >= 0f)
            {
                pendingKick -= dt;
                if (pendingKick < 0f) cmd.kickPressed = true;
            }

            if (target == null || target.IsOut || retarget <= 0f) PickTarget(self);

            Vector3 move = Vector3.zero;
            bool wantEdge = false;
            Vector3? objective = gm != null && gm.Mode != null ? gm.Mode.BotObjective(self) : null;

            bool holdL = target != null && self.handL.heldBrawler == target;
            bool holdR = target != null && self.handR.heldBrawler == target;

            if (holdL && holdR && (!target.IsConscious || haulTime > 0f))
            {
                // haul the body to the closest edge, raise arms, throw
                haulTime += dt;
                Vector3 throwPoint = arena != null ? arena.ThrowPoint(pos) : pos + self.Facing * 5f;
                Vector3 to = throwPoint - pos; to.y = 0f;
                move = to.normalized;
                wantEdge = true;
                cmd.pitch = 75f;
                bool atEdge = to.magnitude < 2.2f || !GroundAhead(self, pos, move, 1.4f) || haulTime > 7f;
                cmd.grabL = cmd.grabR = !atEdge;
                if (atEdge) { haulTime = 0f; retarget = 0.6f; }
            }
            else if (target != null && (objective == null || Near(target.Position, objective.Value, 3f) || Near(pos, target.Position, 2.2f)))
            {
                haulTime = 0f;
                Vector3 to = target.Position - pos; to.y = 0f;
                float d = to.magnitude;
                move = d > 0.85f ? to / d : Vector3.zero;

                if (d < 1.5f)
                {
                    if (!target.IsConscious)
                    {
                        cmd.pitch = -40f;
                        cmd.grabL = cmd.grabR = true;
                        move = d > 0.6f ? to / d * 0.6f : Vector3.zero;
                    }
                    else
                    {
                        grabPlan -= dt;
                        if (grabPlan < -Random.Range(1.5f, 3f)) grabPlan = Random.Range(0.8f, 2f) * skill;
                        bool grappling = grabPlan > 0f;
                        cmd.grabR = grappling;
                        cmd.grabL = grappling && target.Consciousness01 < 0.45f; // two-handed grip → headbutts
                        cmd.pitch = 10f;
                        if (punchCd <= 0f)
                        {
                            cmd.punchPressed = true;
                            punchCd = Random.Range(0.22f, 0.6f) / skill;
                        }
                        if (kickCd <= 0f && Random.value < 0.35f)
                        {
                            cmd.kickPressed = true;
                            kickCd = Random.Range(1.2f, 2.6f);
                        }
                    }
                }
                else
                {
                    cmd.grabL = cmd.grabR = false;
                    if (d < 3.5f && d > 2f && jumpCd <= 0f && Random.value < 0.9f * dt * skill)
                    {
                        cmd.jumpPressed = true;  // flying dropkick
                        pendingKick = 0.22f;
                        jumpCd = Random.Range(3f, 6f);
                    }
                }
            }
            else
            {
                haulTime = 0f;
                cmd.grabL = cmd.grabR = false;
                Vector3 goal = objective ?? RoamPoint(center, arena);
                Vector3 to = goal - pos; to.y = 0f;
                move = to.magnitude > 0.6f ? to.normalized : Vector3.zero;
            }

            // don't walk off the arena by accident
            if (move.sqrMagnitude > 0.01f && !wantEdge && !GroundAhead(self, pos, move, 1.1f))
            {
                Vector3 back = center - pos; back.y = 0f;
                move = back.normalized;
            }

            // unstick by jumping
            Vector3 delta = pos - lastPos; delta.y = 0f;
            lastPos = pos;
            if (move.sqrMagnitude > 0.1f && delta.magnitude < 0.4f * dt) stuck += dt; else stuck = 0f;
            if (stuck > 0.9f && jumpCd <= 0f)
            {
                cmd.jumpPressed = true;
                jumpCd = 1.2f;
                stuck = 0f;
            }

            // bots never climb: let go of the floor or walls if a hand snagged them
            if (self.handL.IsHolding && self.handL.heldWorld) cmd.grabL = false;
            if (self.handR.IsHolding && self.handR.heldWorld) cmd.grabR = false;

            cmd.move = move * Mathf.Lerp(0.75f, 1f, skill);
        }

        static bool Near(Vector3 a, Vector3 b, float r)
        {
            a.y = b.y = 0f;
            return (a - b).sqrMagnitude < r * r;
        }

        Vector3 RoamPoint(Vector3 center, Arena arena)
        {
            if (roamTimer <= 0f)
            {
                float r = arena != null ? arena.Radius * 0.5f : 3f;
                var c = Random.insideUnitCircle * r;
                roamPoint = center + new Vector3(c.x, 0f, c.y);
                roamTimer = Random.Range(2f, 4f);
            }
            return roamPoint;
        }

        void PickTarget(Brawler self)
        {
            retarget = Random.Range(2.5f, 4.5f);
            Brawler best = null;
            float bestScore = float.MaxValue;
            foreach (var b in Brawler.All)
            {
                if (b == self || b.IsOut) continue;
                float d = Vector3.Distance(b.Position, self.Position);
                float score = d;
                if (!b.IsConscious) score -= 3f;              // easy prey
                if (b.participant != null && !b.participant.isBot) score -= 1f; // humans are more fun to pick on
                if (b.IsHeldByOthers) score += 2f;
                score += Random.Range(0f, 2.5f);
                if (score < bestScore) { bestScore = score; best = b; }
            }
            target = best;
        }

        static bool GroundAhead(Brawler self, Vector3 pos, Vector3 dir, float dist)
        {
            Vector3 origin = pos + dir.normalized * dist + Vector3.up * 0.6f;
            int n = Physics.RaycastNonAlloc(origin, Vector3.down, hits, 4.5f, ~0, QueryTriggerInteraction.Ignore);
            for (int i = 0; i < n; i++)
            {
                if (self.Owns(hits[i].collider)) continue;
                if (hits[i].point.y < GameManager.KillHeight + 0.5f) continue;
                return true;
            }
            return false;
        }
    }
}
