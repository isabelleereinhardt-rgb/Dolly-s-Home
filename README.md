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

## Start here

```bash
rokit install          # or: aftman install
rojo serve             # then connect from the Rojo plugin in Studio and press Play
```

Full walkthrough, including what to do if you've never used Rojo:
**[docs/SETUP.md](docs/SETUP.md)**

<details>
<summary>No Rojo? Generate a place file instead.</summary>

```bash
python3 tools/build_rbxmx.py
```

Writes `build/DollysHome.rbxlx` — the whole game as one file you open directly
in Studio — plus three `.rbxmx` bundles for adding the game to a place you
already have. Step by step: **[docs/INSTALL_NO_ROJO.md](docs/INSTALL_NO_ROJO.md)**.

Rojo is still the better workflow if you can get it going: saving a file updates
Studio instantly, where the generated files have to be rebuilt and re-imported
after every change. Both produce an identical hierarchy.

`build/` is gitignored — it's derived from `src/`, so it's rebuilt on demand
rather than committed.
</details>

It runs out of the box. The House builds itself from the layout in
`HouseData.luau` — four floors, real room bounds, the designed hiding spots and
patrol routes, and the cast from `CharacterBuilder.luau`. When you build a map
by hand instead, drop it into `ServerStorage/Maps/TheHouse` and the generated one
gets skipped; a rig in `ServerStorage/Killers/<Name>` likewise wins over the
generated one. Nothing in the gameplay code changes either way.

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
| **The cast** — 9 characters from your mockups | Silhouette + palette | `src/server/Build/CharacterBuilder.luau` |
| The Yard / Menen's Lair / The Graveyard | Not built | — |
| Sound | Wiring done, **ids blank** | `src/shared/Sounds.luau` |

### The two things that need you, not code

1. **Audio.** Every sound id in `src/shared/Sounds.luau` is an empty string. The
   game runs silently and correctly until you fill them in; the moment you paste
   an id, that sound starts playing. The per-killer approach loops are the single
   highest-value audio in the game — they're how a player works out *which* thing
   is hunting them, and therefore whether to run or hold still.
2. **Art passes.** The House and the cast are built from your mockups at
   silhouette level — right proportions, right palette, right signature details,
   but simple geometry. Refining them means editing numbers in `HouseData.luau`
   and `CharacterBuilder.Specs`, or replacing either wholesale via
   `ServerStorage`. See [docs/MAP_BUILDING.md](docs/MAP_BUILDING.md).

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
    Build/                    the House, the cast, and the primitives they share
  client/                     -> StarterPlayer.StarterPlayerScripts
    init.client.luau
    Controllers/              HUD, alerts, vote, results, modals, input, audio, spectate
    UI/                       theme and widget helpers
```
