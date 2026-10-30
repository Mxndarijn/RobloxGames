# 37. Slime walk: wild slimes glide the parade lane and walk back to it when dropped

**Status:** implemented with `FEATURES.Parade` (on). Server-authoritative: the server pivots every lane or returning
slime each Heartbeat (the existing parade replication), the client only adds life on top. No new remote, attribute
or State field; the model `State` stays `"Wild"` while a slime walks back.

## On the lane

- A lane slime glides: its spot is still time left (`ParadeLane.distance`, linear, so a steady pace), its height is
  `LANE_Y` the whole walk (no hop), and its heading is the lane's tangent eased between waypoints
  (`ParadeLane.pointAt`), so it turns gently through the bends.
- The drain: in the last `DRAIN_SECONDS` it climbs onto the curb lip (eased, `DRAIN_LIP_SHARE` of the time), slides
  to the funnel centre and sinks. No hop.
- `ParadeLane.RIDE_SECONDS` is the fountain ride (emerge + slide); the walk starts at the slide mouth right after it.

## Dropped: the return walk

When a carry of a wild slime ends (`Carry.release`: the carrier drops it, is slapped or bonked, leaves the plot zone,
...) and the drop spot has numeric `X` / `Z` (the server passes the carrier's root `Vector3`):

1. `ParadeLane.returnPlan(x, z, lateral, lifetime, now)` plans the walk. The start is the drop spot moved out of the
   landing ring band (`Fountain.clearOfRing`). The slime heads for the nearest point of the lane centreline
   (`ParadeLane.nearest`, lane distance `s` in `0..LENGTH`) on its own lateral line, and merges onto the lane a little
   ahead of it (`RETURN_MERGE` studs, half the walk at most, clamped to `LENGTH`): a quadratic Bezier from the start,
   through the nearest lane point, to the merge point, so it leaves facing the lane and arrives running along it.
   It walks at its own lane pace (`ParadeLane.walkSpeed(lifetime)`), easing in over `RETURN_EASE` seconds after a
   `RETURN_DELAY` pause (it falls out of the carrier's arms first, `WorldView.FALL_SECONDS`).
2. The slime keeps its lifetime and rejoins the flow: `ParadeLane.rejoin(s, lifetime, arriveAt)` sets
   `spawnedAt` / `expiresAt` so the lane timing puts it at the merge point exactly when it arrives
   (`expiresAt - spawnedAt` = `Fountain.wildLifetime`). Dropped near the drain = drains soon after it rejoins.
3. `wild.returning` holds the plan (`{ fromX, fromZ, x1, z1, x2, z2, s, startAt, arriveAt, speed, length }`) and
   `wild.position` the drop spot while it walks (off the lane: `ParadeLane.onLane` is false, so it never emits
   `Drained` from there). `ParadeLane.returnPose(plan, now)` gives its spot and heading. Its height comes from
   `server/WalkHeight` each Heartbeat, over the ground the adapter's ray finds under that spot (from
   `WalkHeight.STEP_UP` above it down to `RAY_DEPTH` below): ground up to `STEP_DOWN` lower, or higher, is a step it
   eases onto; ground further down is a ledge (off the fountain, a jar roof) that it falls off with `GRAVITY` while
   it keeps walking, and lands on; with no ground at all it keeps its height. A step up under its front (one body
   radius ahead) counts already, so its body doesn't clip the step's edge; a drop under its front does not. Over
   its last lane width the ground eases onto `LANE_Y`.
4. `Spawner.step` ends the walk at `arriveAt`: `wild.position` and `wild.returning` go back to nil, the slime is on
   the lane again and walks on from the merge point at the same pace (no jump: the lane pose at `arriveAt` is the
   plan's end point).
5. It stays grabbable the whole way (`Grab` / `Buy $` prompt, `Carry.grab` ends the walk).
6. It walks round things, not through them. While it falls, the server (`WorldView.routeHome` / `planWalk`) finds
   its route from the landing spot to the nearest lane point and swaps it in with
   `Carry.replan(world, id, startAt, route, now)`:
   - Dropped on an upper jar floor: `JarRoute.down` (pure, from WorldLayout) walks it round the deck on
     `DECK_RADIUS`, onto the top of the spiral stair, down it (`floor - 1` turns at `RAMP.walk`) and off at its
     foot on the ground floor. Roblox pathfinding can't use that stair (finer than its navmesh).
   - From there, or from any other drop spot, `WalkRoute.plan` (pure; the world through a probe):
     1. `PathfindingService` with the agent sized to the slime (`WorldView.PATH_AGENT` at least; its radius, its
        height plus a little, so no path under a table top it doesn't fit under) round walls and props, out of the
        jar door and over the moat bridge. Taken only when every leg is clear: a body sweep (a sphere of
        `CLEAR_SHARE` of its radius, from `CLEAR_LOW` over its feet, so curbs don't count) hits nothing solid. A
        path that cuts a corner gets one more search with the agent `PATH_WIDEN` wider. The agent can't jump, so a
        path never hops over a rail. The lock barrier carries a pass-through `PathfindingModifier` and the sweep
        ignores it, so a shut door never blocks it.
     2. Off a roof or the fountain (no clear path from up there): a ledge in one of `WalkRoute.DIRECTIONS` within
        `REACH`, walking down steps it can take on the way; it walks to the edge, drops off (`WalkHeight`) where the
        fall carries it, and takes the path from where it lands. Landings on the ground beat landings on the slide
        (`LOW_WEIGHT`); the walk to the edge and the fall past the edge's lip (`LIP`) are swept too.
     3. No clear way back (boxed in), only one `WalkRoute.MAX_DETOUR` times the straight line or longer, or dropped up
        on the fountain or its slide (`Fountain.upOn`: inside `RING_BAND_INNER`, over `UP_ON_HEIGHT`; the dome, the
        slide head and the railed trough have no way down to walk; under the slide is fine): `Carry.pop` ends the walk and it is on the lane at once, at its merge point,
        with a goo puff (`ParadeView.splash`) where it was and where it lands. At most `MAX_PATHS` engine searches
        and `MAX_DROPS` ledges in a row.
   - While it walks, every `GUARD_INTERVAL` it sweeps the next `GUARD_AHEAD` of its walk (not while it falls, not
     over the last `GUARD_END` studs); something in the way (a trap, a wall, a door) gets a new route from where it
     is the same way (then `GUARD_QUIET` before it looks again). One search per slime at a time.
   - `ParadeLane.reroute(plan, route)` keeps the start, `startAt`, pace and merge point; the slime walks the route
     (`route` / `routeLength` on the plan, facing `RETURN_LOOK` studs ahead), then the Bezier from the route's last
     point onto the lane. `length` / `arriveAt` follow the new route and `rejoin` re-runs, so it still lands on the
     merge point exactly when the lane takes over. A new route starts with the points already walked
     (`ParadeLane.walkedRoute`), so it carries on from where it is, any time, as often as needed.
   - Only the walk planned at `startAt`; a carried slime is never rerouted or popped. A long walk can put its lane
     times after now (`rejoin`); `Scene` still shows it (only a drop waiting for its slide slot has no model).

A drop spot without numeric `X` / `Z` (tests, a missing character), or more than `RETURN_MAX_GAP` studs from the lane
(off the ground, over the void), keeps the old rule: it rests where it was put with
a fresh lifetime and expires there. The boss is never on the lane (`boss-event.md`).

## Escape home

A stolen slime that escapes (`StealService.escape`) still lands on its pad after `World.ESCAPE_BOUNCE_SECONDS`, but
glides there flat (eased, facing the pad) instead of an arc; the client adds no bounces.

## Client life (no hops)

Walking hops, pad fidgets and put-downs came later: see contract/slime-life.md. What stays from here: escaping
slimes glide flat, with no bounce.

- `SlimeLife` schedules no hops: wild and pad slimes breathe (squash), wobble, glance and blink. Wild slimes also
  sway (`params.sway`: a small side-to-side roll and yaw while they walk). A hop plays only when forced through the
  client-only test hook `LifeForce` (`SlimeMotor.FORCE_ATTRIBUTE`).
- `SlimeAnim.tick` emits glances only (`"LookLeft"` / `"LookRight"`); the uploaded `SlimeHop` track is not needed.
- `SlimeBones` keeps the squash, tilt, blink and accessory sway; its hop terms only show on a forced hop.
- `VisualsClient` keeps the gentle idle bob and tilt on slimes the life runner does not animate; `"Escaping"` gets no
  bounce.
