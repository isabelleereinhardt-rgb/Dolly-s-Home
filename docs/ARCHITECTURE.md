# Architecture

How the pieces fit, and why they're arranged this way.

---

## The shape of it

```
                     ┌──────────────────────┐
                     │  GameStateManager    │   the round loop
                     └──────────┬───────────┘
                                │ drives
      ┌──────────────┬──────────┼──────────┬───────────────┐
      ▼              ▼          ▼          ▼               ▼
  MapService   ObjectiveService  KillerService  HelperService  StatsService
      │              │               │
      │              │               ▼
      │              │          KillerAgent  ──reads──▶ NoiseService
      │              │               │                      ▲
      │              │               └──damages──▶ RevivalService
      │              │                                      │
      └── tags ──────┴──── prompts ─────────────────────────┘

  PlayerService  ── owns WalkSpeed for everyone
  SafeZoneService ── owns the InSafeZone attribute
  DataService    ── coins & wins
  TeamService    ── who is in the round
```

Nothing above `KillerAgent` knows how the AI works, and `KillerAgent` doesn't know
a round loop exists. The connections that would have been circular go through
CollectionService tags instead — `HelperService` finds killers by the
`DH_ActiveKiller` tag rather than requiring `KillerService`, and `KillerAgent`
finds safe zones by tag rather than requiring `HelperService`.

---

## How state reaches the client

Two mechanisms, used for different things.

### Attributes, for state

`ReplicatedStorage.DollysHome.State` is a `Configuration` instance. The server
writes attributes to it; Roblox replicates them; the client reads them with
`GetAttribute` and listens with `GetAttributeChangedSignal`.

```lua
-- server
Net.setStateValue(StateKeys.Game.Phase, "Active")

-- client
local phase = Net.getStateValue(StateKeys.Game.Phase, "")
Net.getState():GetAttributeChangedSignal(StateKeys.Game.Phase):Connect(onPhaseChanged)
```

Per-player state (noise, stamina, injured, hidden) lives as attributes **on the
Player object**, which replicates to everyone — so a teammate's HUD can react to
your noise level with no extra plumbing.

This matters most for the noise meter. It updates 10 times a second per player;
on a full server that's 120 updates a second. Over a RemoteEvent that would be
real bandwidth. As an attribute it's free, and it arrives already batched and
delta-compressed by the engine.

Objective progress works the same way: one `Configuration` child per active
objective under `State/Objectives`, with `Current` / `Goal` / `Complete`
attributes. The HUD rebuilds its tracker whenever one changes.

### Remotes, for events

`RemoteEvent`s carry things that aren't state — "a task was just completed",
"here are the round results", "I want to vote". They're listed in
`src/shared/Net.luau`; the server creates them, the client waits for them.

**The countdown timer is a good example of the split.** The server writes
`PhaseEndsAt` — a single `Workspace:GetServerTimeNow()` deadline — once per
phase. Every client renders its own smooth countdown against the synced clock.
One write per phase instead of one per second, and no drift between clients.

---

## Server authority

Everything that matters is decided on the server:

- **Noise** is computed from character velocity that the server measures itself,
  not from a client-reported number. Sprinting is a server-applied `WalkSpeed`
  change, so the server always knows the difference between a walk and a run.
  Speed is read as measured velocity, which means an exploited `WalkSpeed` reads
  as *loud* rather than as free movement.
- **Attacks** revalidate cooldown, range and facing server-side. Spamming the
  `Attack` remote gets you nothing.
- **Revives** recheck the distance between reviver and target, so a forged remote
  can't revive across the map.
- **Purchases** check the price against server-held coins.

The client owns presentation and input intent, nothing else.

---

## The one non-obvious rule: PlayerService owns WalkSpeed

Sprinting, hiding, being downed, carrying crosses and drinking a speed potion all
want to set `WalkSpeed`. If each system wrote it directly, the last one to fire
would win — which is how you end up frozen in place after climbing out of a
locker.

So: **each of those is an attribute, and `PlayerService` recomputes the final
speed from all of them ten times a second.** Attributes are the truth; `WalkSpeed`
is derived. If you add a new movement modifier, add an attribute and a clause in
`PlayerService.resolveSpeed` — don't set `WalkSpeed` from your own service.

---

## The killer AI

`KillerAgent` runs **two coroutines** per killer.

**The think loop** (every 0.15s) decides *where* — it reads
`NoiseService.findAudibleTarget`, runs the state machine, and sets
`self.destination`.

**The navigation loop** handles *how* — it computes a path to the current
destination and walks the waypoints.

They communicate through `self.destination` plus a version counter. Bumping the
version cancels an in-flight path immediately, so a new decision doesn't have to
wait for the old walk to finish. That's what makes a chase feel responsive rather
than laggy: the killer re-targets you the moment you make noise, not when it
arrives where you *were*.

### The four states

| State | Entered when | Behaviour |
|---|---|---|
| **Patrol** | Default | Walks patrol nodes in its favoured zones, mostly in order, sometimes jumping elsewhere so players can't set a watch by it. |
| **Investigate** | Moderate noise (10–29) in range | Walks to the noise, then searches around it — checking hiding spots, wandering within `SearchRadius`. Gives up after `InvestigateMemory × Persistence` seconds. |
| **Chase** | Loud noise (30+), or seen | Runs at chase speed, repaths constantly, attacks in range. Drops back to Investigate after `ChaseGiveUpSilence × Persistence` seconds of silence with no line of sight. |
| **Stunned** | Staked | Frozen. On waking, resumes chasing whoever staked them. |

`Persistence` is per killer — Barbara at 1.5 hunts you for half again as long as
Billy at 0.9. `SearchAggression` scales how often they tear open hiding spots.

### What they can hear

`NoiseService.findAudibleTarget(position, hearingMultiplier)` walks every living
player, works out their noise tier, and returns the highest-priority audible one
(closest breaks ties). Detection range is the tier's range scaled by the killer's
own hearing — Robert (55 studs baseline) hears about 22% further than Barbara (45).

**Skipped entirely**: hidden players, players in a safe zone, downed players,
players out of the round. Being hidden isn't "harder to hear" — it's silent.

---

## Adding things

### A new objective type

1. Add an entry to `ObjectiveData.Definitions` with a `Kind`.
2. If the `Kind` is new, add a `setupYourKind(state)` function in
   `ObjectiveService` and a branch in `beginRound`.
3. Add it to a combination in `ObjectiveData.Combos`.

The HUD picks it up automatically — it renders whatever `Configuration` children
appear under `State/Objectives`.

### A new killer

Add an entry to `KillerData.Profiles` with `Role = "Killer"`. That's it — the
roster is read from the table. Optionally drop a rig into
`ServerStorage/Killers/<Id>`; otherwise `RigBuilder` makes a placeholder from the
colours in the profile.

### A new map

Build it, save it as a Model in `ServerStorage/Maps/<Id>`, tag it (see
[MAP_BUILDING.md](MAP_BUILDING.md)), and add `{ Id = "<Id>", Name = "...",
Description = "...", Enabled = true }` to `Config.Maps`.

### A new remote

Add the name to `REMOTE_EVENTS` in `src/shared/Net.luau`. It's created on the
server and awaited on the client automatically.

---

## Failure behaviour

Deliberate choices about what happens when something goes wrong:

- **DataStores unavailable** → warn once, keep everything in memory, keep
  playing. A save outage should never take the game down.
- **A player's data fails to load** → they get a default profile *and* saving is
  disabled for them, so a transient outage can't overwrite real progress.
- **Map missing tags** → `MapService.validate()` warns with the specific tag
  name; the round still runs.
- **No path to a destination** → the killer walks toward it directly and the
  think loop picks something better next tick.
- **Killer stuck for 4 seconds** → jump, then pick a new destination.
- **An objective can't be set up** (no ritual table, no clock) → warn and
  auto-complete it, so the round is still winnable.
- **The round loop throws** → caught, everything is torn down and reset, and the
  loop restarts after 5 seconds rather than wedging the server.
- **A controller fails to start** → the others still start. Each `start()` is in
  its own `pcall`.

---

## Performance notes

- Noise runs at a fixed 10 Hz, not per frame, and skips replication for changes
  under 0.25.
- Killer thinking runs at ~6.7 Hz. Pathfinding recomputes on destination change,
  not on a timer.
- Floating pickups share **one** `Heartbeat` connection for their spin rather
  than one thread each.
- Noisy tiles use `Touched` with a per-player debounce rather than polling every
  player against every tile.
- Avatar thumbnails on the results screen are cached per user for the session.
