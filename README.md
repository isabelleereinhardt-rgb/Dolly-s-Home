# Dolly's Home

An asymmetric horror survival game for Roblox. Ten to twelve players cooperate to
finish a set of objectives inside a decaying 1920s Louisiana plantation house
while one or two members of a cursed family hunt them.

The family is blind. They hunt entirely by sound. Your noise meter is the whole
conversation between you and the thing in the next room.

```
  Lobby (50s, map vote)  ->  Round start (6s)  ->  The round (10 min)  ->  Results (15s)  ->  repeat
```

**Win** by finishing every objective with at least one player still standing.
**Lose** when the timer hits zero, or when nobody is left.

---

## Start here — no tools required

Three files in **[`build/`](build)**. In Studio, right-click a service in the
Explorer, pick **Insert from File…**, choose the matching file:

| File | Goes into |
|---|---|
| `DollysHome_ReplicatedStorage.rbxmx` | ReplicatedStorage |
| `DollysHome_ServerScriptService.rbxmx` | ServerScriptService |
| `DollysHome_StarterPlayerScripts.rbxmx` | StarterPlayer → StarterPlayerScripts |

Press Play. That's the whole install.

Step by step, including what the Explorer should look like afterwards:
**[docs/INSTALL_NO_ROJO.md](docs/INSTALL_NO_ROJO.md)**

<details>
<summary>Prefer Rojo? (live sync while you edit)</summary>

```bash
rokit install          # or: aftman install
rojo serve             # then connect from the Rojo plugin in Studio
```

Full walkthrough: **[docs/SETUP.md](docs/SETUP.md)**. Rojo's advantage is that
saving a file updates Studio instantly; the `.rbxmx` route means re-importing
when the code changes. Both produce exactly the same hierarchy.

Regenerate the bundles after a code change with `python3 tools/build_rbxmx.py`.
</details>

It runs out of the box. The House builds itself from the layout in
`HouseData.luau` — four floors, real room bounds, the designed hiding spots and
patrol routes. Characters are still placeholder rigs. When you build a map by
hand instead, drop it into `ServerStorage/Maps/TheHouse` and the generated one
gets skipped; nothing in the gameplay code changes.

---

## What's implemented

| System | State | Where |
|---|---|---|
| Round loop, phases, win/loss | Complete | `src/server/Services/GameStateManager.luau` |
| Noise generation, decay, detection tiers | Complete | `src/server/Services/NoiseService.luau` |
| Killer AI (patrol / investigate / chase / stunned) | Complete | `src/server/AI/KillerAgent.luau` |
| Five killers with distinct stats and behaviour | Complete | `src/shared/KillerData.luau` |
| Six objective types, five round combinations | Complete | `src/server/Services/ObjectiveService.luau` |
| Downed state, 30s bleed-out, revives | Complete | `src/server/Services/RevivalService.luau` |
| Hiding spots (locker / bed / table / closet / duct) | Complete | `src/server/Services/HidingService.luau` |
| Stakes: four tiers, damage and stun | Complete | `src/server/Services/CombatService.luau` |
| Robby & Benny, safe zones, the imposter | Complete | `src/server/Services/HelperService.luau` |
| Map voting | Complete | `src/server/Services/VoteService.luau` |
| Coins, Wins, DataStore persistence | Complete | `src/server/Services/DataService.luau` |
| Shop (stakes + consumables) | Basic | `src/server/Services/ShopService.luau` |
| HUD, results screen, modals, spectating | Complete | `src/client/` |
| Ava's graveyard dialogue | Written, waiting on the map | `src/server/Services/AvaService.luau` |
| **The House** — 4 floors, real layout | Built from the mockup | `src/server/Build/HouseData.luau` |
| Designed patrol routes, one per killer | Complete | `HouseData.Routes` |
| Furniture / dressing | Blocks at the right size | `MapBuilder.buildDressing` |
| Character models | Placeholder rigs | `src/server/Build/RigBuilder.luau` |
| The Yard / Menen's Lair / The Graveyard | Not built | — |
| Sound | Wiring done, **ids blank** | `src/shared/Sounds.luau` |

### The two things that need you, not code

1. **Audio.** Every sound id in `src/shared/Sounds.luau` is an empty string. The
   game runs silently and correctly until you fill them in; the moment you paste
   an id, that sound starts playing. The per-killer approach loops are the single
   highest-value audio in the game — they're how a player works out *which* thing
   is hunting them, and therefore whether to run or hold still.
2. **The map.** The greybox is a real, playable two-storey house, but it is grey
   boxes. See [docs/MAP_BUILDING.md](docs/MAP_BUILDING.md) — you tag parts in
   Studio and the code finds them. You never edit a script to add a hiding spot.

---

## Tuning it

Every balance number lives in [`src/shared/Config.luau`](src/shared/Config.luau).
Round length, noise rates, detection ranges, killer speeds, stake damage, coin
payouts, bleed-out time. Nothing else in the codebase hard-codes a balance value.

Some knobs worth knowing about:

```lua
Config.Round.MinPlayersToStart = 1     -- raise to 2+ before you publish
Config.Debug.Verbose           = true  -- print every state transition
Config.Debug.ShowKillerState   = true  -- floating label over each killer's head
Config.Killer.Vision.Enabled   = false -- pure sound-only hunting
Config.Revival.CrawlSpeed      = 4     -- let downed players crawl (0 = can't move)
```

---

## Documentation

- **[SETUP.md](docs/SETUP.md)** — install, run, publish, first-time troubleshooting
- **[MAP_BUILDING.md](docs/MAP_BUILDING.md)** — the tag reference; read this before building a map
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** — how the systems fit together and why
- **[DESIGN_DECISIONS.md](docs/DESIGN_DECISIONS.md)** — where the two design documents disagreed, and which value won

---

## Layout

```
default.project.json          Rojo mapping
src/
  shared/                     -> ReplicatedStorage.Shared
    Config.luau               every tunable number
    KillerData.luau           the family's stats and voice lines
    ObjectiveData.luau        task definitions, round combos, lore notes
    Net.luau                  remotes + the replicated state container
    StateKeys.luau            attribute name constants
    Tags.luau                 CollectionService tag names
    Sounds.luau               sound ids (blank -- fill these in)
    Util.luau                 small helpers
  server/                     -> ServerScriptService.DollysHome
    init.server.luau          bootstrap and start order
    Services/                 one file per system
    AI/KillerAgent.luau       the killer state machine
    Build/                    greybox map and placeholder rig generators
  client/                     -> StarterPlayer.StarterPlayerScripts
    init.client.luau
    Controllers/              HUD, alerts, vote, results, modals, input, audio, spectate
    UI/                       theme and widget helpers
```
