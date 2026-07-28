# Installing without Rojo

Three drag-and-drop files. No terminal, no plugins, no Rojo.

The files live in the **`build/`** folder of this repo:

| File | Goes into |
|---|---|
| `DollysHome_ReplicatedStorage.rbxmx` | **ReplicatedStorage** |
| `DollysHome_ServerScriptService.rbxmx` | **ServerScriptService** |
| `DollysHome_StarterPlayerScripts.rbxmx` | **StarterPlayer → StarterPlayerScripts** |

---

## Getting the files

**From GitHub:** open the `build` folder, click a file, then click **Download**
(the ⤓ button). Do that for all three.

Or just use the three files sent to you in chat.

---

## Installing them

Do this once, in the place you want the game in.

### 1. ReplicatedStorage

1. In Studio, find **ReplicatedStorage** in the Explorer panel.
   (No Explorer? **View → Explorer**.)
2. **Right-click** it → **Insert from File…**
3. Pick `DollysHome_ReplicatedStorage.rbxmx`.

A folder called **Shared** appears inside ReplicatedStorage, with 9 scripts in it.

### 2. ServerScriptService

1. Right-click **ServerScriptService** → **Insert from File…**
2. Pick `DollysHome_ServerScriptService.rbxmx`.

A script called **DollysHome** appears, with `AI`, `Build` and `Services`
folders inside it.

### 3. StarterPlayerScripts

1. Expand **StarterPlayer** in the Explorer.
2. Right-click **StarterPlayerScripts** → **Insert from File…**
3. Pick `DollysHome_StarterPlayerScripts.rbxmx`.

A script called **DollysHomeClient** appears, with `Controllers` and `UI`
folders inside it.

### 4. Press Play

The Output window should say:

```
[DollysHome] server ready -- 10 minute rounds, 50s intermission, 1 map(s) enabled.
[DollysHome] client ready.
```

You'll spawn in the lobby with a map vote on screen. After 50 seconds the House
builds itself and the round starts.

---

## Check it went in right

Your Explorer should look like this:

```
ReplicatedStorage
  └── Shared              (Folder)
        Config, KillerData, Net, ObjectiveData,
        Palette, Sounds, StateKeys, Tags, Util

ServerScriptService
  └── DollysHome          (Script)
        ├── AI            (Folder)  KillerAgent
        ├── Build         (Folder)  HouseData, MapBuilder, Primitives, RigBuilder
        └── Services      (Folder)  15 services

StarterPlayer
  └── StarterPlayerScripts
        └── DollysHomeClient  (LocalScript)
              ├── Controllers (Folder)  8 controllers
              └── UI          (Folder)  Theme, Widgets
```

The **icons matter**. `DollysHome` must be a **Script** (not a ModuleScript) and
`DollysHomeClient` must be a **LocalScript**. If either came in as the wrong
type, delete it and re-insert — inserting into the wrong parent is the usual
cause.

---

## Turning on saving

Coins and Wins use DataStores, which are off in Studio by default. Without them
you'll see this once in the Output, and the game runs fine but forgets progress:

```
[DollysHome/DataService] DataStores unavailable (...). Progress will not persist this session.
```

To switch it on: **File → Game Settings → Security → Enable Studio Access to API
Services**. The place has to be published to Roblox first.

---

## Updating later

When the code changes, download the new `.rbxmx` files and re-insert them —
but **delete the old ones first**, or you'll end up with `Shared` and `Shared`
side by side and Studio will use whichever it finds first.

Order for a clean update:

1. Delete `ReplicatedStorage.Shared`
2. Delete `ServerScriptService.DollysHome`
3. Delete `StarterPlayerScripts.DollysHomeClient`
4. Insert all three new files

Your **map, models and place settings are untouched** by this — the bundles only
contain scripts.

---

## Editing the game

Every balance number is in `ReplicatedStorage → Shared → Config`. Double-click
it in the Explorer and edit it right there in Studio. Round length, noise rates,
killer speeds, stake damage, coin payouts.

Two you'll probably want early:

```lua
Config.Round.MinPlayersToStart = 1      -- raise to 2+ before publishing
Config.Debug.ShowKillerState   = true   -- floating label over each killer
```

Edits you make in Studio stay in your place file. They do **not** flow back to
GitHub — if you want to keep a change permanently, tell me what you changed and
I'll put it in the repo.

---

## Rebuilding the files yourself

If you ever want to regenerate them from source:

```bash
python3 tools/build_rbxmx.py
```

It reads `src/` and writes `build/`. That's the same script that made the files
you have.
