# Setup

This project is a **Rojo** project. The code lives as `.luau` files in git, and
Rojo syncs them into Roblox Studio live. You edit in any editor, Studio updates
as you save, and a code change shows up as a readable diff instead of a binary
`.rbxl` blob.

If you've only ever worked inside Studio, this is the one new idea, and it's
worth twenty minutes: it's what makes the project reviewable, revertible, and
possible for more than one person to work on.

---

## 1. Install the tools

### The easy way (a tool manager)

[Rokit](https://github.com/rojo-rbx/rokit) reads `rokit.toml` in this repo and
installs exactly the versions it pins.

```bash
# macOS / Linux
curl -fsSL https://github.com/rojo-rbx/rokit/releases/latest/download/rokit-installer.sh | bash

# Windows (PowerShell)
irm https://github.com/rojo-rbx/rokit/releases/latest/download/rokit-installer.ps1 | iex
```

Then, from the repo folder:

```bash
rokit install
```

If you already use [Aftman](https://github.com/LPGhatguy/aftman), `aftman install`
works too — `rokit.toml` and `aftman.toml` use the same format, so copy the file
and rename it.

### The manual way

Download the Rojo binary from
[github.com/rojo-rbx/rojo/releases](https://github.com/rojo-rbx/rojo/releases)
and put it on your PATH. You want **Rojo 7.4 or later**.

### The Studio plugin

In Studio: **Plugins → Manage Plugins → find "Rojo"** and install it. Or run
`rojo plugin install` from the command line, which does the same thing.

---

## 2. Run it

From the repo folder:

```bash
rojo serve
```

You'll see something like `Rojo server listening on port 34872`.

In Studio:

1. Open a **new, empty Baseplate**.
2. Open the **Rojo** plugin panel.
3. Click **Connect** (the default address is already right).
4. The Explorer fills in: `ReplicatedStorage.Shared`,
   `ServerScriptService.DollysHome`, `StarterPlayer.StarterPlayerScripts.DollysHomeClient`.

Press **Play**. The output window should say:

```
[DollysHome] server ready -- 10 minute rounds, 50s intermission, 1 map(s) enabled.
[DollysHome] client ready.
```

You'll spawn on a dark platform (the lobby) with a map vote on screen. After 50
seconds the greybox house loads, one or two placeholder killers spawn, and the
round begins.

### Testing with more than one player

**Test → Clients and Servers → 2 players → Start**. This is the only way to
properly exercise revives, the injured-teammate arrows, and the results
scoreboard.

Solo testing works because `Config.Round.MinPlayersToStart` is `1`. **Raise this
to 2 or 3 before you publish** — a one-player round of a co-op game is not the
game.

---

## 3. Turn on saving

Coins and Wins persist through `DataStoreService`, which is disabled in Studio by
default. Without it you'll see this warning once, and the game will run fine but
forget everything:

```
[DollysHome/DataService] DataStores unavailable (...). Progress will not persist this session.
```

To enable it: **Game Settings → Security → Enable Studio Access to API Services**.
This requires the place to be published to Roblox first.

That fallback is deliberate — a DataStore outage should never take the game down,
it should just stop saving. Note that if a player's data fails to *load*, the
service refuses to *save* over it, so a transient outage can't wipe someone's
progress.

---

## 4. Publishing

1. **File → Publish to Roblox As...**, create the place.
2. **Game Settings → Security → Enable Studio Access to API Services** (for DataStores).
3. In `src/shared/Config.luau`, set `Config.Round.MinPlayersToStart` to at least 2.
4. Set `Config.Debug.Verbose = false` and `Config.Debug.ShowKillerState = false`.
5. Fill in the sound ids in `src/shared/Sounds.luau`.

To build a `.rbxl` without Studio open:

```bash
rojo build -o DollysHome.rbxl
```

---

## Troubleshooting

**"DollysHome folder never replicated"** on the client
The server bootstrap didn't run. Check the output window for an error in
`ServerScriptService.DollysHome`. Usually this means Rojo synced the client but
not the server — disconnect and reconnect the plugin.

**Killers stand still and never move**
`PathfindingService` couldn't find a path. In the greybox this shouldn't happen;
on a hand-built map it usually means the floor parts aren't `CanCollide = true`,
or the killer spawned inside geometry. Turn on `Config.Debug.ShowKillerState` to
watch what state each one thinks it's in.

**Warnings about missing tags at round start**
```
[DollysHome/MapService] map "TheHouse" is missing things:
   - Hiding spots: found 0, need at least 3 (tag "DH_HidingSpot")
```
That's `MapService.validate()` doing its job. See
[MAP_BUILDING.md](MAP_BUILDING.md).

**Nothing happens after the vote**
Check `Config.Round.MinPlayersToStart` against how many players are actually in
the server. The output prints `Waiting for players (1/2)` every three seconds
when it's short.

**No sound at all**
Expected. Every id in `src/shared/Sounds.luau` is blank until you fill it in.

**Studio's Script Analysis shows type warnings**
Some are expected — the files that build instances from property tables are
marked `--!nonstrict` for exactly this reason. Warnings never stop the game
running. Genuine mistakes will show up as errors in the output window at
runtime, not in the analysis pane.

---

## Working on it day to day

```bash
rojo serve                 # leave running; Studio picks up saves instantly
stylua src/                # format (config in stylua.toml)
selene src/                # lint (config in selene.toml)
```

Rojo syncs on save, so the loop is: edit file → save → the Script in Studio
updates → press Play. You don't need to restart `rojo serve` unless you add or
rename a *file* (a new script), and even then it usually catches it.
