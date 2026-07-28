# Building maps

The gameplay code never refers to a part by name or by path. It asks
`CollectionService` for everything. That means **you build the map in Studio, tag
the parts, and it works** — no script edits, ever.

Tag a part: **View → Tag Editor**, select the part, type the tag, click the `+`.
Set an attribute: the **Attributes** section at the bottom of the Properties
panel.

---

## Where a map lives

```
ServerStorage/
  Maps/
    TheHouse          <- a Model. This is your map.
    TheYard
    MenensLair
    TheGraveyard
  Lobby               <- optional; replaces the generated lobby
  Killers/
    Bob               <- optional; a rig Model, replaces the placeholder
    Barbara
    ...
```

At round start `MapService` looks for `ServerStorage/Maps/<MapId>`. If it finds a
Model there it clones it into `Workspace.ActiveMap`. If it doesn't, it generates
the greybox instead. So the moment you save a Model named `TheHouse` into
`ServerStorage/Maps`, yours is the one that loads.

To add a whole new map, add an entry to `Config.Maps` in `src/shared/Config.luau`
and set `Enabled = true`. It'll appear in the vote.

---

## The tags

### Spawns

| Tag | On | What it does |
|---|---|---|
| `DH_LobbySpawn` | Part | Where players stand between rounds. Put several down. |
| `DH_PlayerSpawn` | Part | Where players start the round. **Need at least 1; 10–12 is better.** |
| `DH_KillerSpawn` | Part | Where killers enter. **Need at least 1.** Put them far from the player spawns. |

Spawns are used as positions, not orientations — players are placed 3.5 studs
above the part. Invisible, `CanCollide = false` marker parts are ideal.

### Killer navigation

| Tag | On | Attributes | What it does |
|---|---|---|---|
| `DH_PatrolNode` | Part | `Zone` (string) | A waypoint on a patrol route. **Need at least 4.** |
| `DH_Crawlspace` | Part | — | Add *alongside* `DH_PatrolNode`. Only Baby can use it. |

`Zone` should match one of the strings in a killer's `PatrolZones` list in
`src/shared/KillerData.luau` — `Kitchen`, `DiningRoom`, `Library`, `Attic`,
`Cellar`, and so on. Each killer favours their own rooms, which is what makes
Barbara feel like she lives in the kitchen and Robert like he lives in the
library.

If a killer's zones don't exist on your map, they fall back to patrolling every
node rather than standing still. So getting `Zone` wrong degrades the flavour,
not the function. Three or more nodes in a killer's own zones is the threshold
for them to use the preferred set.

### Objectives

| Tag | On | Attributes | What it does |
|---|---|---|---|
| `DH_TaskSpawn` | Part | `TaskType` | A spot an item can spawn. **Need at least 5; 30–40 is comfortable.** |
| `DH_IngredientSpawn` | Part | `Ingredient` | Where one sealing-potion ingredient sits. |
| `DH_RitualTable` | Part | — | Where the four ingredients get combined. One per map. |
| `DH_Clock` | Part | — | The grandfather clock. One per map. |
| `DH_FuseBox` | Part | — | Safe-zone activation objective. One per safe zone. |

`TaskType` is `"Potion"`, `"Cross"`, `"Mirror"`, or `"Any"`. **`"Any"` (or
leaving the attribute off) matches everything** — that's the setting you want for
most spawn points. Use a specific type only when a spot should only ever hold one
kind of thing.

`Ingredient` must be exactly one of `BloodSample`, `HolyWater`, `Garlic`,
`MagicDust`. Put each one where the design document says it lives: blood in the
ritual room, holy water in the cellar, garlic in the kitchen, magic dust in the
study. If a map is missing one, the game falls back to a generic task spawn so
the objective is still finishable.

**How many `DH_TaskSpawn` points do you need?** The largest objective is 14
crosses, all laid out at once, and potions hold 5 more. Aim for at least 25, and
spread them across every room — the whole point is that the house has to be
walked. The generated greybox has about 40.

### Stealth

| Tag | On | Attributes | What it does |
|---|---|---|---|
| `DH_HidingSpot` | Part | `Kind` | Somewhere to hide. **Need at least 3.** |
| `DH_NoisyTile` | Part | `Noise` (number) | Creaky floorboard. Steps on it spike your meter. |
| `DH_Door` | Part | `Noise` (number) | Reserved for a door system; not wired up yet. |

`Kind` is `Locker`, `Closet`, `Bed`, `Table`, or `Duct`. It changes the prompt
text ("Hide in Locker", "Crawl into Duct") and nothing mechanical — all spots
behave the same. Beds and tables should have `CanCollide = false` so players can
walk under them; lockers and closets should be solid.

`Noise` on a tile defaults to `Config.Noise.Actions.CreakyFloor` (12). Put tiles
at chokepoints and around task locations — the design intent is that the fastest
route through a room is the loudest one.

Make noisy tiles *subtly* different from the surrounding floor. Visible if you're
looking, invisible if you're running.

### Landmarks

| Tag | On | Attributes | What it does |
|---|---|---|---|
| `DH_SafeZone` | Part | `Active`, `Radius` | A volume killers refuse to enter. |
| `DH_HelperSpawn` | Part | — | Candidate spots for Robby and Benny to appear. |
| `DH_LoreNote` | Part | `NoteId` | A readable scrap of paper. |
| `DH_AvaGrave` | Part | — | Ava's dialogue anchor. Graveyard map only. |

Safe zones use the part's own size and orientation, so a rotated rectangular part
makes a rotated rectangular zone. Set `Radius` to override with a circle.
`Active = false` starts it dark; the fuse-box objective turns it on. If you don't
set `Active`, it defaults to on.

The design document asks for **three entrances** to each safe zone. Build the
geometry that way — the tagged part is just the trigger volume.

`NoteId` must match a key in `ObjectiveData.LoreNotes` in
`src/shared/ObjectiveData.luau`: `BobLedger`, `BarbaraBills`, `BillyLetter`,
`RobertJournal`, `AvaDiary1`, `AvaDiary2`, `PreviousVictim`. Add your own by
adding entries to that table.

---

## Checking your work

`MapService.validate()` runs automatically every time a map loads and prints
what's missing:

```
[DollysHome/MapService] map "TheHouse" is missing things:
   - Killer spawns: found 0, need at least 1 (tag "DH_KillerSpawn")
   - Task spawn points: found 3, need at least 5 (tag "DH_TaskSpawn")
   See docs/MAP_BUILDING.md for the tag reference.
```

It warns rather than refusing to load, so a half-tagged map is still walkable
while you work on it.

---

## Design notes for The House

From the design document, for whoever builds the real thing:

**Ground floor** — Foyer (central hub, grand staircase), Living Room, Dining
Room (long table, chairs to hide under), Kitchen (noisy tiles, garlic), Pantry,
Library (bookshelves, ladder), Ritual Room (blood sample, candles).

**Second floor** — Master Bedroom (Bob and Barbara's), three Children's Rooms,
Bathroom (bathtub), Study (magic dust), attic access.

**Basement** — Wine Cellar (barrels, holy water), Storage (lockers), Boiler Room
(noisy, steam vents).

**Safe zones** — behind the library bookshelf, in the attic, in the cellar.

**Atmosphere** — dust in moonlight, peeling wallpaper, Spanish moss through
broken windows, flickering candles. Deep browns, muted greens, dusty greys, with
crimson for blood and pale gold for the safe zones.

The one structural note worth repeating: the design asks for the house to feel
like a **labyrinth** — multiple stairwells, hallways that loop back. That's a
geometry decision no amount of tagging can fix afterwards.

---

## Custom killer rigs

Drop a Model into `ServerStorage/Killers/<Name>` where `<Name>` matches an id in
`KillerData.Profiles` (`Bob`, `Barbara`, `Billy`, `Robert`, `Baby`, `Robby`,
`Benny`).

The rig needs exactly three things:

1. A `Humanoid`.
2. A part named `HumanoidRootPart`, set as the model's `PrimaryPart`.
3. A sensible `Humanoid.HipHeight` for the rig's proportions.

Everything else is yours. `KillerAgent` sets `WalkSpeed` from `KillerData` and
drives the rig with `Humanoid:MoveTo`, so a standard R15 rig works with no
changes. If the rig has no Motor6D neck, set `Humanoid.RequiresNeck = false`.

Killers are immortal by design — their HP bar is tracked as a model attribute and
emptying it buys a longer stun, not a kill. Don't let the Humanoid's own health
reach zero.
